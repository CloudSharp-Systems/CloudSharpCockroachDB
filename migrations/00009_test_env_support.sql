-- +goose envsub on
-- REMINDER: Run this migration with the command IDAPI_CRDB_URI="$DEV_URI" GCP_CRED="...your gcp cloud storage access credentials..." go run main.go migrate up


-- +goose Up
IMPORT INTO applications.tb_app CSV DATA('gs://temp_db_csv/tb_app.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;




-- +goose Down
DELETE FROM applications.tb_app;
