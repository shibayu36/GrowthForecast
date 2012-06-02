CREATE TABLE IF NOT EXISTS graphs (
    `id`           INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `service_name` VARCHAR(255) NOT NULL,
    `section_name` VARCHAR(255) NOT NULL,
    `graph_name`   VARCHAR(255) NOT NULL,
    `number`       INT NOT NULL DEFAULT 0,
    `mode`         VARCHAR(255) NOT NULL DEFAULT 'gauge',
    `description`  VARCHAR(255) NOT NULL DEFAULT '',
    `sort`         INT UNSIGNED NOT NULL DEFAULT 0,
    `gmode`        VARCHAR(255) NOT NULL DEFAULT 'gauge',
    `color`        VARCHAR(255) NOT NULL DEFAULT '#00CC00',
    `ulimit`       INT NOT NULL DEFAULT 1000000000,
    `llimit`       INT NOT NULL DEFAULT 0,
    `sulimit`      INT NOT NULL DEFAULT 100000,
    `sllimit`      INT NOT NULL DEFAULT 0,
    `type`         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    `stype`        VARCHAR(255) NOT NULL DEFAULT 'AREA',
    `meta`         TEXT NOT NULL DEFAULT '',
    `created_at`   INT UNSIGNED NOT NULL,
    `updated_at`   INT UNSIGNED NOT NULL,
    UNIQUE  (service_name, section_name, graph_name)
);

CREATE TABLE IF NOT EXISTS prev_graphs (
    `graph_id`     INT NOT NULL,
    `number`       INT NOT NULL DEFAULT 0,
    `subtract`     INT,
    `updated_at`   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
);

CREATE TABLE IF NOT EXISTS prev_short_graphs (
    `graph_id`     INT NOT NULL,
    `number`       INT NOT NULL DEFAULT 0,
    `subtract`     INT,
    `updated_at`   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
);

CREATE TABLE IF NOT EXISTS complex_graphs (
    `id`           INTEGER NOT NULL PRIMARY KEY,
    `service_name` VARCHAR(255) NOT NULL,
    `section_name` VARCHAR(255) NOT NULL,
    `graph_name`   VARCHAR(255) NOT NULL,
    `number`       INT NOT NULL DEFAULT 0,
    `description`  VARCHAR(255) NOT NULL DEFAULT '',
    `sort`         INT UNSIGNED NOT NULL DEFAULT 0,
    `meta`         TEXT NOT NULL DEFAULT '',
    `created_at`   INT UNSIGNED NOT NULL,
    `updated_at`   INT UNSIGNED NOT NULL,
    UNIQUE  (service_name, section_name, graph_name)
);
