package GrowthForecast::Data;

use strict;
use warnings;
use utf8;
use DBIx::Sunny;
use Time::Piece;
use Digest::MD5 qw/md5_hex/;
use List::Util;
use Encode;
use JSON;
use Log::Minimal;
use List::MoreUtils qw/uniq/;
use List::Util qw/first/;

sub new {
    my $class = shift;
    my $root_dir = shift;
    bless { root_dir => $root_dir }, $class;
}

sub dbh {
    my $self = shift;
    $self->{dbh} ||= DBIx::Sunny->connect_cached('dbi:mysql:dbname=growthforecast','nobody','nobody',{
        RaiseError => 1,
        mysql_auto_reconnect => 1,
    });
    $self->{dbh};
}

sub inflate_row {
    my ($self, $row) = @_;
    $row->{created_at} = localtime($row->{created_at})->strftime('%Y/%m/%d %T');
    $row->{updated_at} = localtime($row->{updated_at})->strftime('%Y/%m/%d %T');
    $row->{md5} = md5_hex( Encode::encode_utf8($row->{id}) );
    my $ref =  decode_json($row->{meta}||'{}');
    $ref->{adjust} = '*' if ! exists $ref->{adjust};
    $ref->{adjustval} = '1' if ! exists $ref->{adjustval};
    $ref->{unit} = '' if ! exists $ref->{unit};
    my %result = (
        %$ref,
        %$row
    );
    \%result
}

sub get {
    my ($self, $service, $section, $graph) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?',
        $service, $section, $graph
    );
    return unless $row;
    $self->inflate_row($row);
}

sub get_by_id {
    my ($self, $id) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return unless $row;
    $self->inflate_row($row);
}

sub get_by_id_for_rrdupdate_short {
    my ($self, $id) = @_;
    my $dbh = $self->dbh;

    my $data = $dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return if !$data;

    $dbh->begin_work;
    my $subtract;
    my $prev = $dbh->select_row(
        'SELECT * FROM prev_short_graphs WHERE graph_id = ?',
        $data->{id}
    );
    if ( !$prev ) {
        $subtract = 'U';
        $dbh->query(
            'INSERT INTO prev_short_graphs (graph_id, number, subtract, updated_at) 
                         VALUES (?,?,?,?)',
            $data->{id}, $data->{number}, undef, $data->{updated_at});
    }
    elsif ( $data->{updated_at} != $prev->{updated_at} ) {
        $subtract = $data->{number} - $prev->{number};
        $dbh->query(
            'UPDATE prev_short_graphs SET number=?, subtract=?, updated_at=? WHERE graph_id = ?',
            $data->{number}, $subtract, $data->{updated_at}, $data->{id}
        );
    }
    else {
        if ( $data->{mode} eq 'gauge' || $data->{mode} eq 'modified' ) {
            $subtract = $prev->{subtract};
            $subtract = 'U' if ! defined $subtract;
        }
        else {
            $subtract = 0;
        }
    }
    $dbh->commit;
    $data->{subtract_short} = $subtract;
    $self->inflate_row($data);
}

sub get_by_id_for_rrdupdate {
    my ($self, $id) = @_;
    my $dbh = $self->dbh;

    my $data = $dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return if !$data;

    $dbh->begin_work;
    my $subtract;

    my $prev = $dbh->select_row(
        'SELECT * FROM prev_graphs WHERE graph_id = ?',
        $data->{id}
    );
    
    if ( !$prev ) {
        $subtract = 'U';
        $dbh->query(
            'INSERT INTO prev_graphs (graph_id, number, subtract, updated_at) 
                         VALUES (?,?,?,?)',
            $data->{id}, $data->{number}, undef, $data->{updated_at});
    }
    elsif ( $data->{updated_at} != $prev->{updated_at} ) {
        $subtract = $data->{number} - $prev->{number};
        $dbh->query(
            'UPDATE prev_graphs SET number=?, subtract=?, updated_at=? WHERE graph_id = ?',
            $data->{number}, $subtract, $data->{updated_at}, $data->{id}
        );        
    }
    else {
        if ( $data->{mode} eq 'gauge' || $data->{mode} eq 'modified' ) {
            $subtract = $prev->{subtract};
            $subtract = 'U' if ! defined $subtract;
        }
        else {
            $subtract = 0;
        }
    }

    $dbh->commit;
    $data->{subtract} = $subtract;
    $self->inflate_row($data);
}

sub update {
    my ($self, $service, $section, $graph, $number, $mode, $color ) = @_;
    my $dbh = $self->dbh;
    $dbh->begin_work;

    my $data = $self->get($service, $section, $graph);
    if ( defined $data ) {
        if ( $mode eq 'count' ) {
            $number += $data->{number};
        }
        if ( $mode ne 'modified' || ($mode eq 'modified' && $data->{number} != $number) ) {
            $color ||= $data->{color};
            $dbh->query(
                'UPDATE graphs SET number=?, mode=?, color=?, updated_at=? WHERE id = ?',
                $number, $mode, $color, time, $data->{id}
            );
        }
    }
    else {
        my @colors = List::Util::shuffle(qw/33 66 99 cc/);
        $color ||= '#' . join('', splice(@colors,0,3));
        $dbh->query(
            'INSERT INTO graphs (service_name, section_name, graph_name, number, mode, color, llimit, sllimit, created_at, updated_at) 
                         VALUES (?,?,?,?,?,?,?,?,?,?)',
            $service, $section, $graph, $number, $mode, $color, -1000000000, -100000 ,time, time
        ); 
    }
    my $row = $self->get($service, $section, $graph);
    $dbh->commit;

    $row;
}

sub update_graph {
    my ($self, $id, $args) = @_;
    my @update = map { delete $args->{$_} } qw/service_name section_name graph_name description sort gmode color type stype llimit ulimit sllimit sulimit/;
    my $meta = encode_json($args);
    my $dbh = $self->dbh;
    $dbh->query(
        'UPDATE graphs SET service_name=?, section_name=?, graph_name=?, description=?, sort=?, gmode=?, color=?, type=?, stype=?,
         llimit=?, ulimit=?, sllimit=?, sulimit=?, meta=? WHERE id = ?',
        @update, $meta, $id
    );
    return 1;
}

sub get_services {
    my $self = shift;
    my $rows = $self->dbh->select_all(
        'SELECT DISTINCT service_name FROM graphs ORDER BY service_name',
    );
    my $complex_rows = $self->dbh->select_all(
        'SELECT DISTINCT service_name FROM complex_graphs ORDER BY service_name',
    );
    my @names = uniq map { $_->{service_name} } (@$rows,@$complex_rows);
    \@names
}

sub get_sections {
    my $self = shift;
    my $service_name = shift;
    my $rows = $self->dbh->select_all(
        'SELECT DISTINCT section_name FROM graphs WHERE service_name = ? ORDER BY section_name',
        $service_name,
    );
    my $complex_rows = $self->dbh->select_all(
        'SELECT DISTINCT section_name FROM complex_graphs WHERE service_name = ? ORDER BY section_name',
        $service_name,
    );
    my @names = uniq map { $_->{section_name} } (@$rows,@$complex_rows);
    \@names;
} 

sub get_graphs {
   my $self = shift;
   my ($service_name, $section_name) = @_;
   my $rows = $self->dbh->select_all(
       'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? ORDER BY sort DESC',
       $service_name, $section_name
   );
   my $complex_rows = $self->dbh->select_all(
       'SELECT * FROM complex_graphs WHERE service_name = ? AND section_name = ? ORDER BY sort DESC',
       $service_name, $section_name
   );
   my @ret;
   for my $row ( @$rows ) {
       push @ret, $self->inflate_row($row); 
   }
   for my $row ( @$complex_rows ) {
       push @ret, $self->inflate_complex_row($row); 
   }
   @ret = sort { $b->{sort} <=> $a->{sort} } @ret;
   \@ret;
}

sub get_all_graph_id {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id FROM graphs',
   );
}

sub get_all_graph_name {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id,service_name,section_name,graph_name FROM graphs ORDER BY service_name, section_name, sort DESC',
   );
}


sub remove {
    my ($self, $id ) = @_;
    my $dbh = $self->dbh;
    $dbh->begin_work;
    $dbh->query(
        'DELETE FROM graphs WHERE id = ?',
        $id
    );
    $dbh->query(
        'DELETE FROM prev_graphs WHERE graph_id = ?',
        $id
    );
    $dbh->commit;

}

sub inflate_complex_row {
    my ($self, $row) = @_;
    $row->{created_at} = localtime($row->{created_at})->strftime('%Y/%m/%d %T');
    $row->{updated_at} = localtime($row->{updated_at})->strftime('%Y/%m/%d %T');

    my $ref =  decode_json($row->{meta}||'{}');
    my $uri = join ":", map { $ref->{$_} } qw /type-1 path-1 gmode-1/;
    $uri .= ":0"; #stack

    if ( !ref $ref->{'type-2'} ) {
        $ref->{$_} = [$ref->{$_}] for qw /type-2 path-2 gmode-2 stack-2/;
    }
    my $num = scalar @{$ref->{'type-2'}};
    my @ret;
    for ( my $i = 0; $i < $num; $i++ ) {
        $uri .= ':' . join ":", map { $ref->{$_}->[$i] } qw /type-2 path-2 gmode-2 stack-2/;
        push @ret, {
            type => $ref->{'type-2'}->[$i],
            path => $ref->{'path-2'}->[$i],
            gmode => $ref->{'gmode-2'}->[$i],
            stack => $ref->{'stack-2'}->[$i],
            graph => $self->get_by_id($ref->{'path-2'}->[$i]),
        };        
    }

    $ref->{sumup} = 0 if ! exists $ref->{sumup};
    $ref->{data_rows} = \@ret;
    $ref->{complex_graph} = $uri;
    my %result = (
        %$ref,
        %$row
    );
    \%result
}

sub get_complex {
    my ($self, $service, $section, $graph) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM complex_graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?',
        $service, $section, $graph
    );
    return unless $row;
    $self->inflate_complex_row($row);
}

sub get_complex_by_id {
    my ($self, $id) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM complex_graphs WHERE id = ?',
        $id
    );
    return unless $row;
    $self->inflate_complex_row($row);
}

sub create_complex {
    my ($self, $service, $section, $graph, $args) = @_;
    my @update = map { delete $args->{$_} } qw/description sort/;
    my $meta = encode_json($args);
    $self->dbh->query(
        'INSERT INTO complex_graphs (service_name, section_name, graph_name, description, sort, meta,  created_at, updated_at) 
                         VALUES (?,?,?,?,?,?,?,?)',
        $service, $section, $graph, @update, $meta, time, time
    ); 
    $self->get_complex($service, $section, $graph);
}

sub update_complex {
    my ($self, $id, $args) = @_;
    my @update = map { delete $args->{$_} } qw/service_name section_name graph_name description sort/;
    my $meta = encode_json($args);
    $self->dbh->query(
        'UPDATE complex_graphs SET service_name = ?, section_name = ?, graph_name = ? , 
                                   description = ?, sort = ?, meta = ?, updated_at = ?
                             WHERE id=?',
        @update, $meta, time, $id        
    );
    $self->get_complex_by_id($id);
}

sub remove_complex {
    my ($self, $id ) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'DELETE FROM complex_graphs WHERE id = ?',
        $id
    );
}

1;

