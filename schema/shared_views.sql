-- noinspection SqlResolveForFile

--
-- Aggregates the mileages per bike and month with the month being truncated to the first day of the month.
-- The mileage in this view is the amount of km travelled in that month, not the total value for the given bike any more.
--
CREATE OR REPLACE VIEW v$_mileage_by_bike_and_month AS (
  SELECT b.name                                                                         AS bike,
         date_trunc('month', m.recorded_on)                                             AS month,
         lead(m.amount) OVER (PARTITION BY m.bike_id ORDER BY m.recorded_on) - m.amount AS value
  FROM bikes b
    JOIN milages m ON (m.bike_id = b.id)
  QUALIFY value IS NOT NULL
  ORDER BY bike, month
);


--
-- Aggregated mileage per month, including assorted trips
--
CREATE OR REPLACE VIEW v$_total_mileage_by_month AS (
  WITH sum_of_milages AS (
    SELECT month,
           sum(value) AS value
    FROM v$_mileage_by_bike_and_month
    GROUP BY month
  ), sum_of_assorted_trips AS (
    SELECT date_trunc('month', covered_on) AS month,
           sum(distance) AS value
    FROM assorted_trips
    GROUP BY month
  )
  SELECT m.month AS month,
         m.value + coalesce(t.value, 0) AS value
  FROM sum_of_milages m LEFT OUTER JOIN sum_of_assorted_trips t USING (month)
  ORDER BY month ASC
);
