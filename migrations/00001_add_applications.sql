-- +goose Up
CREATE SCHEMA applications;

CREATE TABLE applications.tb_app (
    app_id          STRING(100) NOT NULL,
    app_description STRING(500) NOT NULL,
    is_enabled      STRING(1) CHECK (is_enabled IN ('N', 'Y')),
    owned_by        STRING(50) NOT NULL,
    created_by      STRING(100) NOT NULL,
    edit_by         STRING(100) NOT NULL,
    edit_date       TIMESTAMP NOT NULL,
    PRIMARY KEY (app_id)
);



-- +goose Down
DROP TABLE applications.tb_app;
DROP SCHEMA applications;
