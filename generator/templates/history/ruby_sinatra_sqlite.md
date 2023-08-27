
## Ruby, Sinatra, SQLite

![Ruby Logo]({{url_for('static', filename='img/ruby-logo.png')}})

Time fly's.
At the time of writing it is already close to 14 years that I wrote a blog about [creating a self-contained MVC application](https://info.michael-simons.eu/2009/07/29/creating-a-self-containing-mvc-application-with-sinatra/).
Back then I was using [Ruby](https://www.ruby-lang.org) a lot and with quite some success with Ruby on Rails in one of my projects.
For what I had in mind that was a bit of overkill though. My use-case was:

- Once a month, write down the value of my bikes odometer
- Aggregate the monthly mileage (back than, it was commuter-bike and an MTB only)
- Grep pictures from my [daily picture blog](https://dailyfratze.de/michael/)

I picked [Sinatra](https://sinatrarb.com) and that was a excellent choice and I really loved it: I could use [DataMapper](https://rom-rb.org) for my persistence, had a RubyDSL for views, and a clear yet concise and easy to understand MVC separation.
Speaking of persistence: I picked one of the most widely used databases in the world, [SQLite](http://www.sqlite.org).
I wanted the project to be truly self-contained and the embedded database was the perfect choice.

If you look at the source, ["biking.rb"](https://github.com/michael-simons/biking2/blob/a10fe3f254db361b85ac6c8fb70f9101dd29fd46/src/main/webapp/public/misc/biking.rb), of this version you'll notice that the data model hardly changed in 14 years. It consists of

- `bikes` (well, obviously contains the bikes)
- `milages` (yes, typo, 1:n relationship from the `bikes`, contains an entry per month per bike, with the absolute value of the odometer of that bike in that month)
- `assorted_trips` (rides I did on rentals etc.)
- `lent_milages` (added in 2021, so that I can track mileages when I lent a bike separately.)

All stats have been derived from those tables in essence.
