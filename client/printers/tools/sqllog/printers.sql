CREATE TABLE jobs(job INT, printer CHAR(255), owner CHAR(255), timestamp TIMESTAMP, event VARCHAR(255));
CREATE INDEX jobs_timestamp_i on jobs(timestamp);

