-- +goose Up
CREATE SCHEMA products;

CREATE TABLE products.tb_server (
    serial_no STRING(50) NOT NULL,
    status STRING(20),
    net_load_capacity INT NOT NULL,
    server_spec STRING(300) NOT NULL,
    cpu STRING(100) NOT NULL,
    ram STRING(100) NOT NULL,
    storage STRING(100) NOT NULL,
    psu STRING(100) NOT NULL,
    fan STRING(100) NOT NULL,
    registration_date DATE NOT NULL,
    last_service_date DATE,
    owned_by STRING(100) NOT NULL,
    location_code STRING(20) NOT NULL,
    rack_code STRING(50) NOT NULL,
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    PRIMARY KEY (serial_no),
    CONSTRAINT check_status CHECK (status IN ('REMOVED', 'IN_REPAIR', 'OFF', 'RUNNING'))
);

CREATE TABLE products.tb_test_graph_edge (
    i INT NOT NULL,
    j INT NOT NULL,
    note STRING(1000),
    PRIMARY KEY (i, j)
);



-- +goose Down
DROP TABLE IF EXISTS products.tb_test_graph_edge;
DROP TABLE IF EXISTS products.tb_server;

DROP SCHEMA IF EXISTS products;

