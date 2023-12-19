-- noinspection SqlResolveForFile

--
-- Stores the managed bikes.
--
CREATE SEQUENCE IF NOT EXISTS bike_id;
CREATE TABLE IF NOT EXISTS bikes (
  id                  INTEGER PRIMARY KEY DEFAULT(nextval('bike_id')),
  name VARCHAR(255)   NOT NULL,
  bought_on           DATE NOT NULL,
  color               VARCHAR(6) DEFAULT 'CCCCCC' NOT NULL,
  decommissioned_on   DATE,
  created_at          DATETIME NOT NULL,
  miscellaneous       BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT bikes_unique_name UNIQUE(name)
);


--
-- Stores the total km travelled with any given bike once per month.
--
CREATE SEQUENCE IF NOT EXISTS milage_id;
CREATE TABLE IF NOT EXISTS milages(
  id                  INTEGER PRIMARY KEY DEFAULT(nextval('milage_id')),
  recorded_on         DATE CHECK (day(recorded_on) = 1)  NOT NULL,
  amount              DECIMAL(8, 2) NOT NULL,
  created_at          DATETIME NOT NULL DEFAULT(now()),
  bike_id             INTEGER NOT NULL,
  CONSTRAINT milage_unique UNIQUE(bike_id, recorded_on),
  CONSTRAINT milage_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id)
);


--
-- In the unlikely case of lending a bike to someone else, this table stores the mileage and trips of the bike while away.
--
CREATE SEQUENCE IF NOT EXISTS lent_milage_id;
CREATE TABLE IF NOT EXISTS lent_milages (
  id                        INTEGER PRIMARY KEY DEFAULT(nextval('lent_milage_id')),
  lent_on                   DATE NOT NULL,
  returned_on               DATE,
  amount /* in KILOMETRE */ DECIMAL(8, 2) NOT NULL,
  created_at                DATETIME NOT NULL,
  bike_id                   INTEGER NOT NULL,
  CONSTRAINT lent_milage_unique UNIQUE(bike_id, lent_on),
  CONSTRAINT lent_milage_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id)
);


--
-- Stores assorted or miscellaneous trips and rides, everything not done on a managed bike.
--
CREATE SEQUENCE IF NOT EXISTS assorted_trip_id;
CREATE TABLE IF NOT EXISTS  assorted_trips (
  id                          INTEGER PRIMARY KEY DEFAULT(nextval('assorted_trip_id')),
  covered_on                  DATE NOT NULL,
  distance /* in KILOMETRE */ DECIMAL(8, 2) NOT NULL
);


--
-- Stores event data.
--
CREATE SEQUENCE IF NOT EXISTS events_id;
CREATE TABLE IF NOT EXISTS events (
  id                  INTEGER PRIMARY KEY DEFAULT(nextval('events_id')),
  name VARCHAR(255)   NOT NULL,
  type                VARCHAR(32) CHECK (type IN ('cycling', 'running')) NOT NULL,
  one_time_only       BOOLEAN NOT NULL,
  CONSTRAINT events_unique_name UNIQUE(name)
);


--
-- Stores results in events.
--
CREATE TABLE IF NOT EXISTS results (
  event_id            INTEGER NOT NULL,
  achieved_at         DATE NOT NULL,
  duration            INTEGER NOT NULL,
  distance            DECIMAL(9, 3) NOT NULL,
  PRIMARY KEY (event_id, achieved_at),
  FOREIGN KEY (event_id) REFERENCES events(id)
);


--
-- Stores imported Garmin activities (See https://github.com/michael-simons/garmin-babel)
--
CREATE TABLE IF NOT EXISTS garmin_activities (
  garmin_id                     BIGINT PRIMARY KEY,
  name                          VARCHAR(512) NOT NULL,
  started_on                    TIMESTAMP  NOT NULL,
  activity_type                 VARCHAR(64) NOT NULL,
  sport_type                    VARCHAR(64),
  distance /* in KILOMETRE */   DECIMAL(9, 3),
  elevation_gain /* in METRE */ DECIMAL(9, 3),
  duration                      INTEGER NOT NULL,
  elapsed_duration              INTEGER,
  moving_duration               INTEGER ,
  v_o_2_max                     TINYINT,
  start_longitude               DECIMAL(9, 6),
  start_latitude                DECIMAL(8, 6),
  end_longitude                 DECIMAL(9, 6),
  end_latitude                  DECIMAL(8, 6),
  gear                          VARCHAR(512)
);


--
-- Add a flag whether the GPX data is available or not
--
ALTER TABLE garmin_activities ADD COLUMN IF NOT EXISTS gpx_available BOOLEAN DEFAULT false;


--
-- Add a certificate per result
--
ALTER TABLE results ADD COLUMN IF NOT EXISTS certificate BOOLEAN DEFAULT false;

--
-- Change certificate to type
--
ALTER TABLE results ALTER COLUMN certificate TYPE VARCHAR(8);
ALTER TABLE results ALTER COLUMN certificate SET DEFAULT NULL;
UPDATE results SET certificate = null WHERE certificate = 'false';
UPDATE results SET certificate = 'pdf' WHERE certificate = 'true';


--
-- Maintenance
--
CREATE SEQUENCE IF NOT EXISTS bike_maintenance_id;
CREATE TABLE IF NOT EXISTS bike_maintenance (
    id                        INTEGER PRIMARY KEY DEFAULT(nextval('bike_maintenance_id')),
    bike_id                   INTEGER NOT NULL,
    conducted_on              DATE NOT NULL,
    milage /* in KILOMETRE */ DECIMAL(8, 2) NOT NULL,
    CONSTRAINT bike_maintenance_unique UNIQUE(bike_id, conducted_on),
    CONSTRAINT bike_maintenance_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id)
);

CREATE SEQUENCE IF NOT EXISTS maintenance_li_id;
CREATE TABLE IF NOT EXISTS bike_maintenance_line_items (
    id              INTEGER PRIMARY KEY DEFAULT(nextval('maintenance_li_id')),
    maintenance_id  INTEGER NOT NULL,
    item            VARCHAR(512) NOT NULL,
    CONSTRAINT line_item_maintenance_fk FOREIGN KEY(maintenance_id) REFERENCES bike_maintenance(id)
);


--
-- Specs
--
CREATE SEQUENCE IF NOT EXISTS bike_spec_id;
CREATE TABLE IF NOT EXISTS bike_specs (
    id                        INTEGER PRIMARY KEY DEFAULT(nextval('bike_spec_id')),
    bike_id                   INTEGER NOT NULL,
    pos                       INTEGER NOT NULL,
    item                      VARCHAR(512) NOT NULL,
    removed                   BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT bike_spec_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id)
);
