
## Python, Flask, DuckDB

<i class="bi bi-github"></i> [michael-simons/biking3](https://github.com/michael-simons/biking3){.lead}

![Python Logo]({{url_for('static', filename='img/python-logo-only.png')}}){.giant}

My life's focussed changed a lot over the last 5 years.
First, the whole biking thing escalated "a bit" and then I discovered running.
For some time I had "Michael is an athlete (wishful thinking)" to my profile bios.
I think that wishful thinking is done.
While I still do all the things I tracked on this site as a hobby and not on amateur or pro level, I think I am pretty good at it.
And while I do have some writing projects in the pipeline, my time is sadly limited after all.
Upgrading to Spring Boot 3 is about time for this site, but I am stuck on some components for which there are no Jakarta EE pendants. 
I could have just dropped the location features, but than what's the point in keeping it in the above-mentioned book?
My database model and Hibernate 6.x work pretty well together, no issue there.
But [AngularJS](https://angularjs.org) v1 as a UI? 
How long can I get away with it?

In the end, I don't feel like upgrading.
And keep on maintaining.
But I wanted my stats and my sport site.

What I could justify was something new, but something without additional maintenance burden.
Enter [DuckDB](https://duckdb.org), Python and [Flask](https://flask.palletsprojects.com/en/2.3.x/) with Jinja2. 

I am totally in love with DuckDB: It is a fast, embedded OLAP database which can do all the SQL "tricks" and then some. 
It is my goto tool even for CSV transformation.
And again, I could just copy over my schema.
Python and Flask: Well, why not? 
I wanted to do something different for a while now and it reminds me about Sinatra in the best possible way.
And: DuckDB has great Python bindings.

For what I had as SQL disguised as [jOOQ](https://www.jooq.org) code in the Spring Boot application (for example [this part here](https://github.com/michael-simons/biking2/blob/a10fe3f254db361b85ac6c8fb70f9101dd29fd46/src/main/java/ac/simons/biking2/statistics/StatisticService.java#L123) that generates a query that computes the monthly and total average over all years and bikes), I created actual views as API.
[`v_monthly_average`](https://github.com/michael-simons/biking3/blob/5466d0b5479009eb9da05f4ef8b117f7b937796b/schema/api.sql#L159-L178) for example represents the same query as above.
Of course, the computational complexity did not disappear by magic.
The aggregation of the computed mileage per month is just part of another [view](https://github.com/michael-simons/biking3/blob/5466d0b5479009eb9da05f4ef8b117f7b937796b/schema/shared_views.sql#L21-L37) that is used in the query.

All interaction from Python are only `FROM xxx` queries which makes the actual application really easy to reason about. The [physical ER-Diagram](https://github.com/michael-simons/biking3/tree/main/generator/static/docs/schema.mermaid) for all tables is generated directly from the live database.

I don't want to maintain a cloud / server / something setup of a software at the moment, but I also didn't want to mangle any existing static site generator into my use-case.
But there's [Frozen Flask](https://pythonhosted.org/Frozen-Flask/), which essentially crawls a Flask application and renders all URLs it finds, ready to be scp'ed somewhere where HTML can be delivered.
For adding new data or manipulate existing one I don't really need a fancy UI, the interaction I need is scripted now with a handful of shell-scripts. 
