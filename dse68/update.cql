USE test;
UPDATE daily_tiered_import_size set imported_tier_data_size= imported_tier_data_size+76167372947893 where day = 20240725 and tier_level = 1 and hour = -1 and pgc_key = -1;
SELECT * from daily_tiered_import_size where day = 20240725 and tier_level = 1;
