### CloudSharpCockroachDB
Cockroach DB Migrations for CloudSharp main database.

## Prerequisite
Create a .env file in the project folder with the following content:
- DEV_DB: development database name
- DEV_URI: cockroach db connection uri
```
DEV_DB=appdatabasedev
DEV_URI="postgresql://..."
```

## Usage
Create development database
```
make dev-database
```

Migrate up (this will migrate to the latest version)
```
IDAPI_CRDB_URI="$DEV_URI" go run main.go migrate up
```

Migrate down (this will migrate 1 version down)
```
IDAPI_CRDB_URI="$DEV_URI" go run main.go migrate down
```
