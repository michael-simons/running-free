from datetime import datetime
from flask_frozen import Freezer

import click
import duckdb
import flask
import os
import pandas


def site(database: str):
    assets_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), './static/assets'))
    gallery_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), './static/gallery'))

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
    app.jinja_env.globals.update({
        'tz': 'Europe/Berlin',
        'now': now,
        'max_year': 2022,
        'assets_present': os.path.isdir(assets_dir),
        'gallery_present': os.path.isdir(gallery_dir)
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

    @app.route("/gear/")
    def gear():
        with db.cursor() as con:
            bikes = con.execute('FROM v_bikes').df()

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
