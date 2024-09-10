# biking3

A collection of scripts, a database schema and a site-generator that creates https://biking.michael-simons.eu.
The repository is provided for educational purposes.
The whole software is catered for my needs and I doubt that is that useful for other people.

## Database schema

The SQL commands have all been developed and tested with [DuckDB](https://duckdb.org) >= 0.8.1.
They are separated in 3 categories:

- Base tables
- Shared views (not particular helpful in isolation)
- API (Views to be accessed by all sort of clients)

## Site generator

The site generator is essentially a [Flask application](https://flask.palletsprojects.com/en/2.3.x/) which can be run with a local development server.
The `app.py` entry-point can however be run with either `run` or `build` commands.
The latter will freeze the site and generate static HTML files.

## Bookmarks

The following list is a collection of projects that might be useful in adding stuff:

* https://github.com/SamR1/FitTrackee
* https://github.com/komoot/staticmap
* https://protomaps.com
* https://github.com/maplibre/martin
