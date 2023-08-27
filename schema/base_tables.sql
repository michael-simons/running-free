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
  CONSTRAINT milage_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id) ON DELETE CASCADE
);


--
-- In the unlikely case of lending a bike to someone else, this table stores the mileage and trips of the bike while away.
--
CREATE SEQUENCE IF NOT EXISTS lent_milage_id;
CREATE TABLE IF NOT EXISTS lent_milages (
  id                  INTEGER PRIMARY KEY DEFAULT(nextval('lent_milage_id')),
  lent_on             DATE NOT NULL,
  returned_on         DATE,
  amount              DECIMAL(8, 2) NOT NULL,
  created_at          DATETIME NOT NULL,
  bike_id             INTEGER NOT NULL,
  CONSTRAINT lent_milage_unique UNIQUE(bike_id, lent_on),
  CONSTRAINT lent_milage_bike_fk FOREIGN KEY(bike_id) REFERENCES bikes(id) ON DELETE CASCADE
);


--
-- Stores assorted or miscellaneous trips and rides, everything not done on a managed bike.
--
CREATE SEQUENCE IF NOT EXISTS assorted_trip_id;
CREATE TABLE IF NOT EXISTS  assorted_trips (
  id                  INTEGER PRIMARY KEY DEFAULT(nextval('assorted_trip_id')),
  covered_on          DATE NOT NULL,
  distance            DECIMAL(8, 2) NOT NULL
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
