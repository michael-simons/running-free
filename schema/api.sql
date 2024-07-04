-- noinspection SqlResolveForFile

--
-- All active bikes
--
CREATE OR REPLACE VIEW v_active_bikes AS (
  SELECT * FROM bikes
  WHERE NOT miscellaneous
    AND decommissioned_on IS NULL
  ORDER BY name
);


--
-- All bikes, their last mileage and the years (as a list) in which they have been favoured over others.
--
CREATE OR REPLACE VIEW v_bikes AS (
  WITH mileage_by_bike_and_year AS (
    SELECT bike, year(month) AS year, sum(value) AS value
    FROM v$_mileage_by_bike_and_month
    GROUP BY all
  ), ranked_bikes AS (
    SELECT bike, year, dense_rank() OVER (PARTITION BY year ORDER BY value DESC) AS rnk
    FROM mileage_by_bike_and_year
    QUALIFY rnk = 1
    ORDER BY year
  ), years AS (
    SELECT bike, list(year ORDER BY year) AS value
    FROM ranked_bikes
    GROUP BY all
  ), lent AS (
    SELECT bike_id, sum(amount) AS value FROM lent_milages GROUP BY ALL
  ), last_milage AS (
     SELECT bike_id, last(amount) AS value
     FROM milages GROUP BY bike_id ORDER BY last(recorded_on)
  )
  SELECT bikes.*,
         coalesce(last_milage.value, 0) + coalesce(lent.value, 0) AS last_milage,
         coalesce(years.value, []) as favoured_in
  FROM bikes
  LEFT OUTER JOIN years ON years.bike = bikes.name
  LEFT OUTER JOIN lent ON lent.bike_id = bikes.id
  LEFT OUTER JOIN last_milage ON last_milage.bike_id = bikes.id
  WHERE NOT hide
  ORDER BY last_milage desc, bought_on, decommissioned_on, name
);


--
-- Summary over all bikes
--
CREATE OR REPLACE VIEW v_summary AS (
  WITH sum_of_milages AS (
    SELECT month,
           sum(value) AS value
    FROM v$_mileage_by_bike_and_month
    GROUP BY ROLLUP (month)
  ), sum_of_assorted_trips AS (
    SELECT date_trunc('month', covered_on) AS month,
           sum(distance) AS value
    FROM assorted_trips
    GROUP BY ROLLUP (month)
  ),
  summary AS (
    SELECT min(m.month)                                                                 AS since,
           max(m.month)                                                                 AS last_recording,
           arg_min(m.month, m.value + coalesce(t.value, 0)) FILTER (WHERE m.value <> 0) AS worst_month,
           min(m.value + coalesce(t.value, 0)) FILTER (WHERE m.value <> 0)              AS worst_month_value,
           arg_max(m.month, m.value + coalesce(t.value, 0))                             AS best_month,
           max(m.value + coalesce(t.value, 0))                                          AS best_month_value
    FROM sum_of_milages m LEFT OUTER JOIN sum_of_assorted_trips t USING (month)
    WHERE m.month IS NOT NULL
  )
  SELECT s.*,
         m.value + t.value                                     AS total,
         total / date_diff('month', s.since, s.last_recording) AS avg_per_month
  FROM sum_of_milages m,
       sum_of_assorted_trips t,
       summary s
  WHERE m.month IS NULL
    AND t.month IS NULL
    AND s.last_recording IS NOT NULL
);


--
-- Mileages over all bikes and assorted trips in the current year (year-today)
--
CREATE OR REPLACE VIEW v_ytd_summary AS (
  WITH sum_of_milages AS (
    SELECT month,
           sum(value) AS value
    FROM v$_mileage_by_bike_and_month
    WHERE month BETWEEN date_trunc('year', current_date()) AND date_trunc('month', current_date())
    GROUP BY ROLLUP (month)
  ),
  sum_of_assorted_trips AS (
    SELECT date_trunc('month', covered_on) AS month,
           coalesce(sum(distance),      0) AS value
    FROM assorted_trips
    WHERE month BETWEEN date_trunc('year', current_date()) AND date_trunc('month', current_date())
    GROUP BY ROLLUP (month)
  ),
  summary AS (
    SELECT max(d.range)::date                                                  AS last_recording,
           arg_min(d.range, coalesce(m.value, 0) + coalesce(t.value, 0))::date AS worst_month,
           min(coalesce(m.value, 0) + coalesce(t.value, 0))                    AS worst_month_value,
           arg_max(d.range, coalesce(m.value, 0) + coalesce(t.value, 0))::date AS best_month,
           max(coalesce(m.value, 0) + coalesce(t.value, 0))                    AS best_month_value
    FROM range(date_trunc('year', current_date()), date_trunc('year', current_date()) + interval 12 month, interval 1 month) d
      LEFT OUTER JOIN sum_of_milages m ON m.month = d.range
      LEFT OUTER JOIN sum_of_assorted_trips t ON t.month = d.range
    WHERE m.value IS NOT NULL OR t.value IS NOT NULL
  ),
  sum_of_milages_by_bike AS (
    SELECT bike,
           sum(value) AS value
    FROM v$_mileage_by_bike_and_month
    WHERE month BETWEEN date_trunc('year', current_date()) AND date_trunc('month', current_date())
    GROUP BY bike
  )
  SELECT s.*,
         (SELECT arg_max(bike, value) FROM sum_of_milages_by_bike)                                           AS preferred_bike,
         coalesce(m.value, 0) + coalesce(t.value, 0)                                                         AS total,
         total / date_diff('month', date_trunc('year', current_date()), s.last_recording + interval 1 month) AS avg_per_month
  FROM sum_of_milages m,
       sum_of_assorted_trips t,
       summary s
  WHERE m.month IS NULL
    AND t.month IS NULL
    AND s.last_recording IS NOT NULL
);


--
-- Monthly totals in the current year.
--
CREATE OR REPLACE VIEW v_ytd_totals AS (
  SELECT * replace(strftime(month, '%B') AS month)
  FROM v$_total_mileage_by_month
  WHERE month >= date_trunc('year', current_date())
    AND month <= last_day(date_trunc('month', current_date()))
);


--
-- Monthly totals by bike in the current, can be safely pivoted on the bike.
--
CREATE OR REPLACE VIEW v_ytd_bikes AS (
    SELECT mbbm.*
    FROM v$_mileage_by_bike_and_month mbbm
    JOIN bikes b ON (b.name = mbbm.bike)
    WHERE month >= date_trunc('year', current_date())
      AND month <= last_day(date_trunc('month', current_date()))
      AND NOT b.miscellaneous
);


--
-- Monthly average over all, including 0 values for months in which no ride was done.
--
CREATE OR REPLACE VIEW v_monthly_average AS (
  WITH
    months AS (SELECT range AS value FROM range('2023-01-01'::date, '2024-01-01'::date, INTERVAL 1 month)),
    data AS (
      SELECT monthname(month)     AS month,
             min(value)           AS minimum,
             max(value)           AS maximum,
             round(avg(value), 2) AS average
      FROM v$_total_mileage_by_month x
      GROUP BY ROLLUP(monthname(month))
    )
  SELECT monthname(months.value)   AS month,
         coalesce(data.minimum, 0) AS minimum,
         coalesce(data.maximum, 0) AS maximum,
         coalesce(data.average, 0) AS average
  FROM months
     FULL OUTER JOIN data
    ON data.month = monthname(months.value)
  ORDER BY month(months.value)
);


--
-- Reoccurring events and their results. Results will be a structured list object per row.
--
CREATE OR REPLACE VIEW v_reoccurring_events AS (
  SELECT name, list({
    achieved_at: achieved_at,
    age_group: f_dlo_agegroup(achieved_at),
    distance: distance,
    time: lpad(cast(duration//3600 AS VARCHAR), 2, '0') || ':' || lpad(cast((duration%3600)//60 AS VARCHAR), 2, '0') || ':' || lpad(cast(duration%3600%60 AS VARCHAR), 2, '0'),
    pace: if(distance IS NOT NULL, cast(floor(duration/distance/60) AS int) || ':' || lpad(cast(round(duration/distance%60, 0)::int AS VARCHAR), 2, '0'), null),
    certificate: if(certificate IS NOT NULL, strftime(achieved_at, '%Y-%m-%d') || ' ' || name || '.' || certificate, null)
  } ORDER BY achieved_at)
  FROM events e JOIN results r ON r.event_id = e.id
  WHERE NOT one_time_only
    AND NOT hide
  GROUP BY ALL
  ORDER BY name
);


--
-- One time only events and the explicit result therein.
--
CREATE OR REPLACE VIEW v_one_time_only_events AS (
  SELECT name,
         achieved_at,
         f_dlo_agegroup(achieved_at) AS age_group,
         distance,
         lpad(cast(duration//3600 AS VARCHAR), 2, '0') || ':' || lpad(cast((duration%3600)//60 AS VARCHAR), 2, '0') || ':' || lpad(cast(duration%3600%60 AS VARCHAR), 2, '0') AS time,
         if(distance IS NOT NULL, cast(floor(duration/distance/60) AS int) || ':' || lpad(cast(round(duration/distance%60, 0)::int AS VARCHAR), 2, '0'), null) AS pace,
         if(certificate IS NOT NULL, strftime(achieved_at, '%Y-%m-%d') || ' ' || name || '.' || certificate, null) AS certificate
  FROM events e JOIN results r ON r.event_id = e.id
  WHERE one_time_only
    AND NOT hide
  GROUP BY ALL
  ORDER BY achieved_at, name
);


--
-- Aggregated mileages per year and bike up excluding the current year
--
CREATE OR REPLACE VIEW v_mileage_by_bike_and_year AS (
  WITH max_recordings AS (
    SELECT bike_id, max(recorded_on) AS value FROM milages GROUP BY bike_id
  )
  SELECT bikes.id AS id,
         name,
         year(recorded_on) - CASE WHEN recorded_on = mr.value AND strftime(mr.value, '%m-%d') <> '01-01' THEN 0 ELSE 1 END AS year,
         round(amount - coalesce(lag(amount) OVER (PARTITION BY name ORDER BY recorded_on),0)) AS mileage
  FROM bikes
    JOIN milages ON milages.bike_id = bikes.id
    JOIN max_recordings mr ON mr.bike_id = bikes.id
  WHERE (strftime(recorded_on, '%m-%d') = '01-01' OR (bikes.decommissioned_on IS NOT NULL AND recorded_on = mr.value))
  ORDER BY name, year
);


--
-- The median and p95 pace per distance (5k, 10k, 21k and Marathon) and year (formatted as MI:SS)
--
CREATE OR REPLACE VIEW v_pace_percentiles_per_distance_and_year AS (
  SELECT value AS distance, year,
         list_transform(percentiles, pace -> cast(floor(pace/60) AS int) || ':' || lpad(cast(round(pace%60, 0)::int AS VARCHAR), 2, '0')) AS percentiles
  FROM v$_pace_percentiles_per_distance_and_year
);


--
-- The median and p95 pace per distance (5k, 10k, 21k and Marathon) and year (as Seconds/METRE)
--
CREATE OR REPLACE VIEW v_pace_percentiles_per_distance_and_year_seconds AS (
  SELECT value AS distance, year, percentiles
  FROM v$_pace_percentiles_per_distance_and_year
);


--
-- Conducted maintenances
--
CREATE OR REPLACE VIEW v_maintenances AS (
  WITH src AS (
    SELECT b.id, name,
           conducted_on, milage,
           i.id AS item_id,
           {
             item: item,
             lasted: milage - lag(milage) OVER(PARTITION BY bike_id, item ORDER BY conducted_on)
           } AS item
    FROM bikes b
      JOIN bike_maintenance m ON m.bike_id = b.id
      JOIN bike_maintenance_line_items i ON maintenance_id = m.id
  )
  SELECT * EXCLUDE (item_id, item), list(item ORDER BY item_id) AS items
  FROM src
  GROUP BY ALL
  ORDER BY name, conducted_on
);


--
-- Specs
--
CREATE OR REPLACE VIEW v_specs AS (
  SELECT b.id, name, pos, item, removed
  FROM bikes b
    JOIN bike_specs s ON s.bike_id = b.id
  ORDER BY name, pos
);


--
-- Health metrics
--
CREATE OR REPLACE VIEW v_health_by_age AS (
  SELECT year(ref_date) AS year,
         ifnull(chronological_age, year - 1979) AS chronological_age,
         cast(round(avg(biological_age) FILTER (WHERE biological_age IS NOT NULL)) AS int) AS avg_biological_age,
         cast(round(avg(resting_heart_rate) FILTER (WHERE resting_heart_rate IS NOT NULL)) AS int) AS avg_resting_heart_rate,
         round(avg(weight) FILTER (WHERE weight IS NOT NULL), 2) AS avg_weight,
         round(avg(body_fat) FILTER (WHERE body_fat IS NOT NULL), 2) AS avg_body_fat,
         cast(round(avg(avg_stress_level) FILTER (WHERE avg_stress_level IS NOT NULL)) AS int) AS avg_stress_level,
         round(avg(vo2max_biometric) FILTER (WHERE vo2max_biometric IS NOT NULL), 2) AS avg_vo2max,
         round(avg(vo2max_running) FILTER (WHERE vo2max_running IS NOT NULL), 2) AS avg_vo2max_running,
         round(avg(vo2max_cycling) FILTER (WHERE vo2max_cycling IS NOT NULL), 2) AS avg_vo2max_cycling
  FROM health_metrics
  GROUP BY ALL
  HAVING (
    avg_biological_age NOT NULL OR avg_resting_heart_rate NOT NULL OR
    avg_weight NOT NULL OR avg_body_fat NOT NULL
  )
  ORDER BY year, chronological_age
);


--
-- SHOES
--
CREATE OR REPLACE VIEW v_shoes AS
SELECT make || ' ' || model AS name, * EXCLUDE(make, model)
FROM shoes
WHERE picture IS NOT NULL
 AND NOT hide
ORDER BY first_run_on, last_run_on;
