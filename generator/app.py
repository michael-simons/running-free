from datetime import datetime

from flask_frozen import Freezer
from pathlib import Path

import click
import duckdb
import flask
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
        'fmt_double': lambda v: format(v, '.2f')
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
        'max_year': 2022,
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
            ytd_bikes = db.execute('PIVOT (FROM v_ytd_bikes) ON bike USING first(value)').df().set_index('month')
            monthly_averages = db.execute('FROM v_monthly_average').df()

        return flask.render_template('mileage.html.jinja2', bikes=bikes, ytd_summary=ytd_summary, ytd_totals=ytd_totals,
                                     ytd_bikes=ytd_bikes, monthly_averages=monthly_averages)

    @app.route("/achievements/")
    def achievements():
        with db.cursor() as con:
            reoccurring_events = con.execute('FROM v_reoccurring_events').fetchall()
            one_time_only_events = con.execute('FROM v_one_time_only_events').df()

        return flask.render_template('achievements.html.jinja2', reoccuring_events=reoccurring_events,
                                     one_time_only_events=one_time_only_events)

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

                return flask.render_template((gear_dir.parts[-1] / template).as_posix(), bike=bike,
                                             mileage_by_year=mileage_by_year, pd=pandas)
            except (ValueError, jinja2.exceptions.TemplateNotFound):
                flask.abort(404)

        with db.cursor() as con:
            bikes = con.execute('FROM v_bikes').df()
        if gear_dir.is_dir():
            bikes['has_details'] = bikes['name'].map(lambda n: gear_dir.joinpath(gear_template(n)).is_file())

        return flask.render_template('gear.html.jinja2', bikes=bikes)

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
