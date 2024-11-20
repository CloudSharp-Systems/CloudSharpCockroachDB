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

CREATE TABLE applications.tb_app_data_control (
    app_id         STRING(100) NOT NULL,
    control_name   STRING(50) NOT NULL,
    control_type   STRING(50) NOT NULL,
    control_level  STRING(50) NOT NULL,
    control_value  STRING(250) NOT NULL,
    control_note   STRING NOT NULL,
    is_enabled     STRING(1) CHECK (is_enabled IN ('N', 'Y')),
    edit_by        STRING(100) NOT NULL,
    edit_date      TIMESTAMP NOT NULL,
    PRIMARY KEY (app_id, control_name, control_type, control_level, control_value),
    CONSTRAINT fk_app FOREIGN KEY (app_id) REFERENCES applications.tb_app (app_id)
);

CREATE TABLE applications.tb_central_system_log (
    log_id         STRING(150) NOT NULL,
    app_id         STRING(100) NOT NULL,
    system_name    STRING(100) NOT NULL,
    trace_id       STRING(100),
    record_type    STRING(50) CHECK (record_type IN ('NOTE', 'WARNING', 'ERROR', 'GOOD')),
    record_key     STRING(150),
    record_value1  STRING(250),
    record_value2  STRING(250),
    record_value3  STRING(250),
    record_value4  STRING(250),
    record_value5  STRING(250),
    record_message STRING NOT NULL,
    record_note    STRING NOT NULL,
    edit_by        STRING(100) NOT NULL,
    edit_time      TIMESTAMP NOT NULL,
    PRIMARY KEY (log_id),
    CONSTRAINT fk_app FOREIGN KEY (app_id) REFERENCES applications.tb_app (app_id)
);

CREATE TABLE applications.tb_program_status (
    program_id        STRING(150) NOT NULL,
    app_id            STRING(100) NOT NULL,
    program_type      STRING(50) NOT NULL,
    program_status    STRING(20) NOT NULL CHECK (program_status IN ('ERROR', 'WARNING', 'GOOD')),
    last_trace_id     STRING(100) NOT NULL,
    last_log_time     TIMESTAMP NOT NULL,
    notes             STRING NOT NULL,
    max_idle_interval INT NOT NULL,
    resource_sep      STRING(100) NOT NULL,
    resource          STRING(100) NOT NULL,
    program_path      STRING(2000) NOT NULL,
    execution_command STRING(2000) NOT NULL,
    edit_by           STRING(100) NOT NULL,
    edit_time         TIMESTAMP NOT NULL,
    PRIMARY KEY (program_id, app_id),
    CONSTRAINT fk_app FOREIGN KEY (app_id) REFERENCES applications.tb_app (app_id)
);

CREATE VIEW applications.v_app_data_control AS
SELECT
    c.app_id,
    a.is_enabled AS is_app_enabled,
    c.control_name,
    c.control_type,
    c.control_level,
    c.control_value,
    c.control_note,
    c.is_enabled AS is_control_enabled,
    c.edit_by,
    c.edit_date
FROM applications.tb_app_data_control c
INNER JOIN applications.tb_app a
ON c.app_id = a.app_id;




-- +goose StatementBegin
CREATE FUNCTION applications.central_system_log_volume(date_offset INT, target_app_id STRING)
RETURNS SETOF RECORD AS $$
SELECT
    target_app_id AS app_id,
    log_date AS log_date,
    SUM(log_count) AS log_count
FROM (
    SELECT CAST(edit_time AS DATE) AS log_date, COUNT(*) AS log_count
    FROM applications.tb_central_system_log
    WHERE app_id = target_app_id AND edit_time >= (current_date - date_offset)
    GROUP BY CAST(edit_time AS DATE)

    UNION ALL

    SELECT pads.log_date AS log_date, 0 AS log_count
    FROM (
	SELECT current_date - offset_index.day_index AS log_date
	FROM (SELECT generate_series(0, date_offset) AS day_index) offset_index
    ) pads
) agg
GROUP BY log_date;
$$ LANGUAGE SQL;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE applications.update_task_statuses(
    target_app_id STRING,
    target_program_type STRING,
    target_edit_by STRING
)
LANGUAGE SQL AS $$
UPDATE applications.tb_program_status
SET
    program_status = 'ERROR',
    notes = 'The task has stopped updating its status!',
    edit_by = target_edit_by,
    edit_time = current_timestamp
WHERE
    app_id = target_app_id
    AND program_type = target_program_type
    AND extract(epoch FROM (current_timestamp - last_log_time)) / 60 > max_idle_interval;
$$;
-- +goose StatementEnd





-- +goose Down
DROP PROCEDURE IF EXISTS applications.update_task_statuses;

DROP FUNCTION IF EXISTS applications.central_system_log_volume;

DROP VIEW IF EXISTS applications.v_app_data_control;

DROP TABLE IF EXISTS applications.tb_program_status;
DROP TABLE IF EXISTS applications.tb_central_system_log;
DROP TABLE IF EXISTS applications.tb_app_data_control;
DROP TABLE IF EXISTS applications.tb_app;

DROP SCHEMA IF EXISTS applications;

