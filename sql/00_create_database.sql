-- =====================================================================
-- STEP 00 - Create the database
-- Run this ONCE while connected to the default "postgres" database.
-- pgAdmin: right-click Databases > Create > Database... also works.
-- =====================================================================
DROP DATABASE IF EXISTS retail_analytics;
CREATE DATABASE retail_analytics
    WITH ENCODING = 'UTF8'
    TEMPLATE = template0;

-- Now reconnect to retail_analytics and run scripts 01 onwards.
