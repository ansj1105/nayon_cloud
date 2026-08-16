FROM flyway/flyway:10.17.3-alpine

COPY db/migration /flyway/sql
