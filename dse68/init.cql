CREATE KEYSPACE test WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
USE test;

CREATE TABLE daily_tiered_import_size (
    day int,
    tier_level int,
    hour int,
    pgc_key int,
    imported_lg_key_count counter,
    imported_tier_data_size counter,
    PRIMARY KEY ((day, tier_level), hour, pgc_key)
) WITH gc_grace_seconds = 1;
