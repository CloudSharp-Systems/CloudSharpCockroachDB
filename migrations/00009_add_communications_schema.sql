-- +goose Up
CREATE SCHEMA communications;

CREATE TABLE communications.tb_email_header (
	email_id STRING(100) NOT NULL PRIMARY KEY,
	uploaded_by STRING(100) NOT NULL,
	uploaded_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	scheduled_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	status STRING(20) NOT NULL,
	note STRING(250) NOT NULL,
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	INDEX (status, scheduled_time DESC)
);

CREATE TABLE communications.tb_message_backlog_spec (
	spec_id STRING(100) NOT NULL PRIMARY KEY DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
	message_type STRING(20) NOT NULL,
	template_id STRING(100) NULL,
	schedule STRING(20) NOT NULL, -- CRON expression
	audit_schedule STRING(20) NOT NULL,
	backlog_window FLOAT NOT NULL, -- allowed window to complete the backlog
	is_in_audit CHAR NOT NULL CHECK (is_in_audit IN ('Y', 'N')),
	is_enabled CHAR NOT NULL CHECK (is_enabled IN ('Y', 'N')),
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL
);

CREATE TABLE communications.tb_message_backlog (
	backlog_id STRING(100) NOT NULL PRIMARY KEY DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
	spec_id STRING(100) NOT NULL,
	due_time TIMESTAMP NOT NULL,
	status STRING(20) NOT NULL,
	note STRING(250) NOT NULL,
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	CONSTRAINT fk_backlog_spec FOREIGN KEY (spec_id) REFERENCES communications.tb_message_backlog_spec(spec_id)
);


-- +goose Down
DROP TABLE IF EXISTS communications.tb_message_backlog;
DROP TABLE IF EXISTS communications.tb_message_backlog_spec;
DROP TABLE IF EXISTS communications.tb_email_header;

DROP SCHEMA IF EXISTS communications;

