--
-- Computes the age group according to DLV / DLO, see
-- https://www.leichtathletik.de/fileadmin/user_upload/006_Wir-im-DLV/03_Struktur/DLV_Satzung_Ordnungen/Deutsche_Leichtathletik-Ordnung.pdf
--
CREATE OR REPLACE FUNCTION f_dlo_agegroup(ref_date) AS (
  WITH age_in_years AS (
    SELECT date_diff('year', value::date, ref_date::date) AS value
    FROM user_profile dob
    WHERE dob.name = 'date_of_birth'
  ), gender AS (
    SELECT CASE value WHEN 'male' THEN 'M' WHEN 'female' THEN 'W' ELSE '-' END AS value
    FROM user_profile
    WHERE name = 'gender'
  )
  SELECT
    CASE
      WHEN a.value >= 0  AND a.value < 7  THEN g.value || 'K U8'
      WHEN a.value >= 7  AND a.value < 12 THEN g.value || 'K U' || (20-(20-1-a.value)//2*2)
      WHEN a.value >= 12 AND a.value < 20 THEN g.value || 'J U' || (20-(20-1-a.value)//2*2)
      WHEN a.value >= 20 AND a.value < 23 THEN g.value || ' U23'
      WHEN a.value >= 23 AND a.value < 30 THEN g.value
      ELSE g.value || least((a.value // 5)*5, 95)
    END
  FROM age_in_years a, gender g
);

--
-- Computes the pace for a given distance in meters over a duration in seconds
--
CREATE OR REPLACE FUNCTION f_pace(distance, duration) AS (
  SELECT if(distance IS NOT NULL, cast(floor(duration/distance/60) AS int) || ':' || lpad(cast(round(duration/distance%60, 0)::int AS VARCHAR), 2, '0'), null)
);

--
-- Formats a duration in seconds as time hh:mm:ss
--
CREATE OR REPLACE FUNCTION f_format_duration(duration) AS (
  SELECT lpad(cast(duration//3600 AS VARCHAR), 2, '0') || ':' || lpad(cast((duration%3600)//60 AS VARCHAR), 2, '0') || ':' || lpad(cast(duration%3600%60 AS VARCHAR), 2, '0')
);

--
-- Unifies a Garmin activity
--
CREATE OR REPLACE FUNCTION f_unify_activity_type(activity_type) AS (
  SELECT CASE
    WHEN activity_type IN ('gravel_cycling', 'mountain_biking', 'cycling', 'road_biking') THEN 'cycling'
    WHEN activity_type IN ('track_running', 'running', 'treadmill_running') THEN 'running'
    WHEN activity_type IN ('lap_swimming', 'open_water_swimming', 'swimming') THEN 'swimming'
  END
);
