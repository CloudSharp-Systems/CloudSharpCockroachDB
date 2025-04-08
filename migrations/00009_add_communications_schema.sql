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


-- +goose Down
DROP TABLE IF EXISTS communications.tb_email_header;

DROP SCHEMA IF EXISTS communications;

