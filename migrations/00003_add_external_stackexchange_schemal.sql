-- +goose Up
CREATE SCHEMA external_stackexchange;

CREATE TABLE external_stackexchange.tb_cs_educator_posts (
    id STRING(100) NOT NULL,
    post_type_id STRING(100) NOT NULL,
    creation_date TIMESTAMP NOT NULL,
    score INT NOT NULL,
    view_count INT NOT NULL,
    body STRING NOT NULL,
    owner_user_id STRING(100) NOT NULL,
    last_editor_user_id STRING(100) NOT NULL,
    last_edit_date TIMESTAMP NOT NULL,
    last_activity_date TIMESTAMP NOT NULL,
    title STRING(200) NOT NULL,
    tags STRING(200) NOT NULL,
    answer_count INT NOT NULL,
    comment_count INT NOT NULL,
    content_license STRING(50) NOT NULL,
    PRIMARY KEY (id ASC)
);

CREATE TABLE external_stackexchange.tb_cs_educator_raw (
    id STRING(100) NOT NULL,
    post_type_id STRING(100) NOT NULL,
    creation_date STRING(50) NOT NULL,
    score STRING(10) NOT NULL,
    view_count STRING(10) NOT NULL,
    body STRING NOT NULL,
    owner_user_id STRING(100) NOT NULL,
    last_editor_user_id STRING(100) NOT NULL,
    last_edit_date STRING(50) NOT NULL,
    last_activity_date STRING(50) NOT NULL,
    title STRING(500) NOT NULL,
    tags STRING(500) NOT NULL,
    answer_count STRING(10) NOT NULL,
    comment_count STRING(10) NOT NULL,
    content_license STRING(50) NOT NULL
);




-- +goose Down
DROP TABLE IF EXISTS external_stackexchange.tb_cs_educator_raw;
DROP TABLE IF EXISTS external_stackexchange.tb_cs_educator_posts;

DROP SCHEMA IF EXISTS external_stackexchange;

