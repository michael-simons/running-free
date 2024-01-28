from datetime import datetime

from flask_frozen import Freezer
from numpy import nan
from pathlib import Path
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import PolynomialFeatures

import click
import duckdb
import flask
import functools
import jinja2.exceptions
import pandas


def site(database: str):
    db = duckdb.connect(database=database, read_only=True)

    now = datetime.now()

    app = flask.Flask(__name__, static_url_path="/")
    app.jinja_options["autoescape"] = lambda _: True
    app.jinja_options['extensions'] = ['jinja_markdown.MarkdownExtension']
    app.jinja_env.filters.update({
        'fmt_month': lambda v: v.strftime('%B %Y'),
        'fmt_date': lambda v: v.strftime('%Y-%m-%d') if not (v is None or v is pandas.NaT) else '',
        'fmt_time': lambda v: v.strftime('%H:%M'),
        'fmt_datetime': lambda v: v.strftime('%Y-%m-%dT%H:%M:%S'),
        'fmt_double': lambda v: format(v, '.2f'),
        'fmt_int': lambda v: format(v, '.0f')
    })
    app.jinja_env.tests.update({
        'nat': lambda v: v is pandas.NaT
    })

    root = Path(__file__).parent
    assets_dir = root / app.static_folder / "assets"
    gallery_dir = root / app.static_folder / "gallery"
    gear_dir = root / app.template_folder / "gear"

    app.jinja_env.globals.update({
        'tz': 'Europe/Berlin',
        'now': now,
        'max_year': 2023,
        'assets_present': assets_dir.is_dir(),
        'gallery_present': gallery_dir.is_dir()
    })

    @app.route('/')
    def index():
        with db.cursor() as con:
            summary = con.execute('FROM v_summary').df()
        return flask.render_template('index.html.jinja2', summary=summary)

    @app.route("/mileage/")
    def mileage():
        with db.cursor() as con:
            bikes = con.execute('FROM v_active_bikes').df()
            ytd_summary = db.execute('FROM v_ytd_summary').df()
            ytd_totals = db.execute('FROM v_ytd_totals').df()
            ytd_bikes_query = """
                SELECT * replace(strftime(month, '%B') AS month) 
                FROM (PIVOT (FROM v_ytd_bikes) ON bike USING first(value) ORDER by month)
            """
            ytd_bikes = db.execute(ytd_bikes_query).df().set_index('month').fillna(0)
            monthly_averages = db.execute('FROM v_monthly_average').df()

        return flask.render_template('mileage.html.jinja2', bikes=bikes, ytd_summary=ytd_summary, ytd_totals=ytd_totals,
                                     ytd_bikes=ytd_bikes, monthly_averages=monthly_averages)

    @app.route("/achievements/")
    def achievements():
        max_year = flask.current_app.jinja_env.globals.get('max_year')
        with db.cursor() as con:
            reoccurring_events = con.execute('FROM v_reoccurring_events').fetchall()
            one_time_only_events = con.execute('FROM v_one_time_only_events').df().replace({nan: None})
            pace_percentiles = con.execute(
                'FROM v_pace_percentiles_per_distance_and_year_seconds WHERE distance <> ? AND year <= ?',
                ['Marathon', max_year]).df()

        def pivot(distance, data):
            percentiles = data.loc[data['distance'] == distance]['percentiles']
            years = zip(*functools.reduce(lambda x, y: x + [y], percentiles, []))
            return list(years)

        development = {
            'years': pace_percentiles['year'].unique().tolist(),
            'percentiles': {
                '5k': pivot('5', pace_percentiles),
                '10k': pivot('10', pace_percentiles),
                '21k': pivot('21', pace_percentiles)
            }
        }

        return flask.render_template('achievements.html.jinja2', reoccuring_events=reoccurring_events,
                                     one_time_only_events=one_time_only_events, development=development)

    def gear_template(name: str):
        """Normalizes the name into the gear folder, throwing on attempted path traversal"""
        return gear_dir.joinpath(name + ".html.jinja2").resolve().relative_to(gear_dir)

    @app.route("/gear/")
    @app.route("/gear/<name>/")
    def gear(name: str = None):
        if name is not None and not gear_dir.is_dir():
            flask.abort(404)
        if name is not None:
            try:
                template = gear_template(name)
                with db.cursor() as con:
                    bike = con.execute('FROM v_bikes WHERE name = ?', [name]).df()
                    mileage_by_year = con.execute('FROM v_mileage_by_bike_and_year WHERE name = ?', [name]).df()
                    maintenance = con.execute('FROM v_maintenances WHERE name = ?', [name]).df()
                    specs = con.execute('FROM v_specs WHERE name = ?', [name]).df()

                x = mileage_by_year['year'].to_numpy().reshape(-1, 1)
                y = mileage_by_year['mileage'].to_numpy()

                x = PolynomialFeatures(degree=3, include_bias=False).fit_transform(x)
                model = LinearRegression()
                model.fit(x, y)
                trend = model.predict(x)

                return flask.render_template((gear_dir.parts[-1] / template).as_posix(), bike=bike,
                                             mileage_by_year=mileage_by_year, pd=pandas, trend=trend,
                                             maintenance=maintenance, specs=specs)
            except (ValueError, jinja2.exceptions.TemplateNotFound):
                flask.abort(404)

        with db.cursor() as con:
            bikes = con.execute('FROM v_bikes').df()
            shoes = con.execute('FROM v_shoes').df()
        if gear_dir.is_dir():
            bikes['has_details'] = bikes['name'].map(lambda n: gear_dir.joinpath(gear_template(n)).is_file())

        return flask.render_template('gear.html.jinja2', bikes=bikes, shoes=shoes)

    @app.route("/history/")
    def history():
        return flask.render_template('history.html.jinja2')

    return app


@click.group()
def cli():
    pass


@cli.command()
@click.argument('database', type=click.Path(exists=True), default='../sport.db')
def run(database: str):
    """Runs the site in development mode"""
    site(database).run(debug=True)


@cli.command()
@click.argument('database', type=click.Path(exists=True))
@click.argument('destination', type=click.Path(file_okay=False, resolve_path=True))
@click.option('--base-url', default='https://biking.michael-simons.eu')
def build(database: str, destination: str, base_url: str):
    """Builds the site"""
    app = site(database)
    app.config['FREEZER_DESTINATION'] = destination
    app.config['FREEZER_BASE_URL'] = base_url
    freezer = Freezer(app)
    freezer.freeze()


if __name__ == '__main__':
    cli()
