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
    SELECT bike, list(year) AS value
    FROM ranked_bikes
    GROUP BY all
  ), lent AS (
    SELECT bike_id, sum(amount) AS value FROM lent_milages GROUP BY ALL
  ), last_milage AS (
     SELECT bike_id, last(amount) AS value
     FROM milages GROUP BY bike_id ORDER BY last(recorded_on) ASC
  )
  SELECT bikes.*,
         coalesce(last_milage.value, 0) + coalesce(lent.value, 0) AS last_milage,
         coalesce(years.value, []) as favoured_in
  FROM bikes
  LEFT OUTER JOIN years ON years.bike = bikes.name
  LEFT OUTER JOIN lent ON lent.bike_id = bikes.id
  LEFT OUTER JOIN last_milage ON last_milage.bike_id = bikes.id
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
           sum(distance) AS value
    FROM assorted_trips
    WHERE month BETWEEN date_trunc('year', current_date()) AND date_trunc('month', current_date())
    GROUP BY ROLLUP (month)
  ),
  summary AS (
    SELECT max(m.month)                                                                 AS last_recording,
           arg_min(m.month, m.value + coalesce(t.value, 0)) FILTER (WHERE m.value <> 0) AS worst_month,
           min(m.value + coalesce(t.value, 0)) FILTER (WHERE m.value <> 0)              AS worst_month_value,
           arg_max(m.month, m.value + coalesce(t.value, 0))                             AS best_month,
           max(m.value + coalesce(t.value, 0))                                          AS best_month_value
    FROM sum_of_milages m LEFT OUTER JOIN sum_of_assorted_trips t USING (month)
    WHERE m.month IS NOT NULL
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
         m.value + t.value                                                                                   AS total,
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
    SELECT mbbm.* replace(strftime(month, '%B') AS month)
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
    distance: distance,
    time: lpad(duration//3600, 2, '0') || ':' || lpad((duration%3600)//60, 2, '0') || ':' || lpad(duration%3600%60, 2, '0'),
    pace: cast(floor(duration/distance/60) AS int) || ':' || lpad(floor(duration/distance%60)::int, 2, '0')
  })
  FROM events e JOIN results r ON r.event_id = e.id
  WHERE NOT one_time_only
  GROUP BY ALL
  ORDER BY name
);


--
-- One time only events and the explicit result therein.
--
CREATE OR REPLACE VIEW v_one_time_only_events AS (
  SELECT name,
         achieved_at,
         distance,
         lpad(duration//3600, 2, '0') || ':' || lpad((duration%3600)//60, 2, '0') || ':' || lpad(duration%3600%60, 2, '0') AS time,
         cast(floor(duration/distance/60) AS int) || ':' || lpad(floor(duration/distance%60)::int, 2, '0') AS pace
  FROM events e JOIN results r ON r.event_id = e.id
  WHERE one_time_only
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
         year(recorded_on) - CASE WHEN recorded_on = mr.value THEN 0 ELSE 1 END AS year,
         round(amount - coalesce(lag(amount) OVER (PARTITION BY name ORDER BY recorded_on),0)) AS mileage
  FROM bikes
    JOIN milages ON milages.bike_id = bikes.id
    JOIN max_recordings mr ON mr.bike_id = bikes.id
  WHERE (strftime(recorded_on, '%m-%d') = '01-01' OR (bikes.decommissioned_on IS NOT NULL AND recorded_on = mr.value))
  ORDER BY name, year
);


--
-- The median and p95 pace per distance (5k, 10k, 21k and Marathon) and year
--
CREATE OR REPLACE VIEW v_median_and_p95_pace_per_distance_and_year AS (
  WITH ranges AS (
    SELECT CASE
             WHEN distance BETWEEN  4.75 AND  6.0 THEN '5'
             WHEN distance BETWEEN  9.5  AND 12.0 THEN '10'
             WHEN distance BETWEEN 19.95 AND 25.2 THEN '21'
             WHEN distance >= 42 THEN 'Marathon'
             ELSE null
           END AS range,
           year(started_on) AS year,
           percentile_cont([0.5, 0.95]) WITHIN GROUP(ORDER BY duration/distance DESC) AS percentiles
    FROM garmin_activities
    WHERE activity_type = 'running'
      AND range IS NOT NULL
    GROUP BY range, year
    ORDER BY try_cast(range AS integer) ASC NULLS LAST, year
  ), readable_paces AS (
    SELECT * REPLACE(list_transform(percentiles, pace -> cast(floor(pace/60) AS int) || ':' || lpad(floor(pace%60)::int, 2, '0')) AS percentiles)
    FROM ranges
  )
  SELECT range AS distance,
         year,
         percentiles[1] AS median_pace,
         percentiles[2] AS p95
  FROM readable_paces
);
