require 'runt'

module MephistoGoogleCalendarPlugin

  # Configure me!
  DATE_FORMAT = '%d.%m.%Y'
  TIME_FORMAT = '%H:%M Uhr'

  # Returns the next events from the calendar specified by address
  def get_events(address, items = 5, mode = 'upcoming')

    # Get calendar data from Google
    data = scan address
    calendar = parse data

    # Order events by date, earlier dates first
    events = calendar.events.sort{|e1,e2| e1.start_date <=> e2.start_date}

    # Align the event time data to the local time zone
    events = events.each{|e| e.start_time = e.start_time.getlocal}

    # Remove inappropriate events, according to the given mode
    # TODO: Support more modes
    if mode == 'upcoming'
      # Check for recurring events and remove them from the array of events. They will come back if they actually gonna happen.
      revents = events.select{|e| !e.rrule.blank?}
      revents.each{|e| events.delete(e)}

      # Calculate next appearance of recurring events
      unless revents.blank?
        nevents = []
        revents.each do |revent|
          if revent.rrule_as_hash['UNTIL'].blank?
            # UNTIL has no value
            if revent.start_date > Date.today
              # if start_date lies in the future, the next date is start_date itself, we can leave revent untouched
              nevents << revent
            else
              expr = rrule_to_runt(revent)
              next_dates = calc_next_date(expr, Date.today)

              unless next_dates.blank?
                diff = revent.start_date - revent.end_date
                revent.start_date = next_dates.first.to_date
                revent.end_date = next_dates.first.to_date + diff
                nevents << revent
              end
            end
          end
        end
        events += nevents
      end
  
      # Remove old events
      events = events.reject{|e| e.end_date < Date.today}

    end

    # Sort the events chronologically and select only the number of events as configured in items
    return events.sort{|e1,e2| e1.start_date <=> e2.start_date}[0..[events.length,items-1].min]

  end

  # Takes an google calendar address and a number of items (optional) and returns a pretty HTML short list
  def gcal_shortlist(address, items = 5, mode = 'upcoming')

    # Retrieve the events
    events = get_events(address, items, mode)

    html = '<div class="gcal shortlist">'

    unless events.blank?
      html += '<ul>'

        events.each do |event|
          html += '<li>'
          html += "<div class=\"summary\">#{event.summary}</div>"
        
          if event.start_date == event.end_date
            # Events with same date at start and end need a time display
            # This time format may be configured at the top of the file
            html += "<div class=\"info\">#{event.start_date.strftime(DATE_FORMAT)}&nbsp;&ndash;&nbsp;#{event.start_time.strftime(TIME_FORMAT)}</div>"
          else
            # For one silly reason, Google sends us end_date on full-day-events equipped with one day later. We have to decrement this.
            event.end_date -= 1
         
            # After this decrementation, start_date and end_date may be equal. In this case, we display just one of them
            if event.start_date == event.end_date
              html += "<div class=\"info\">#{event.start_date.strftime(DATE_FORMAT)}</div>"
            else
              html += "<div class=\"info\">#{event.start_date.strftime(DATE_FORMAT)}&nbsp;&ndash;&nbsp;#{event.end_date.strftime(DATE_FORMAT)}</div>"
            end
          end

          html += "<div class=\"info\">#{event.location}</div>"
          html += '</li>'
        end
      html += '</ul>'
    else
      html += '<div class="no_events">Keine Veranstaltungen verf&uuml;gbar.</div>' # This says 'No events available'. Please translate to your language.
  end
 
    html += '</div>'

    return html

  end

  # Convert from an events RRULE to a Runt Temporal Expression
  def rrule_to_runt(event)

    # The rrules contain unusual weekday shortcuts. We have to translate them for Runt.
    weekdays = { "SU" => 0,
                 "MO" => 1,
                 "TU" => 2,
                 "WE" => 3,
                 "TH" => 4,
                 "FR" => 5,
                 "SA" => 6}

    freq = event.rrule_as_hash['FREQ'] unless event.rrule_as_hash['FREQ'].blank?
    interval = event.rrule_as_hash['INTERVAL'] unless event.rrule_as_hash['INTERVAL'].blank?
    last_date = Date.parse(event.rrule_as_hash['UNTIL']) unless event.rrule_as_hash['UNTIL'].blank?
    bydays = event.rrule_as_hash['BYDAY'].split(',') unless event.rrule_as_hash['BYDAY'].blank?
    bymonthday = event.rrule_as_hash['BYMONTHDAY'] unless event.rrule_as_hash['BYMONTHDAY'].blank?

    # Just a small shortcut
    start_date = event.start_date
    end_date = event.end_date

    if freq == 'YEARLY'

      expr = Runt::REYear.new(start_date.month, start_date.day, end_date.month, end_date.day)

      unless interval.blank?
        expr = expr & Runt::EveryTE.new(start_date,interval,Runt::DPrecision::Precision.year)
      end

    elsif freq == 'MONTHLY'

      if !bymonthday.blank?
        expr = Runt::REMonth.new(bymonthday, end_date.day)
      elsif !bydays.blank?
        expr = Runt::DIMonth.new(bydays.first.to_i, weekdays[bydays.first[-2..-1]])
      else
        # This case should never happen, but it's here for the sake security.
        expr = Runt::REMonth.new(start_date.day, end_date.day)
      end

      unless interval.blank?
         expr = expr & Runt::EveryTE.new(start_date,interval,Runt::DPrecision::Precision.month)
      end

    elsif freq == 'WEEKLY'

      expr = Runt::Collection.new()

      bydays.each do |byday|
        expr = expr | Runt::DIWeek.new(weekdays[byday])
      end

      unless interval.blank?
         expr = expr & Runt::EveryTE.new(start_date,interval,Runt::DPrecision::Precision.week)
      end

    elsif freq == 'DAILY'

      expr = Runt::Collection.new()

      0.upto(6) do |day|
        expr = expr | Runt::DIWeek.new(day)
      end

      unless interval.blank?
         expr = expr & Runt::EveryTE.new(start_date,interval,Runt::DPrecision::Precision.day)
      end

    end

    return expr

  end

  # Check wether the given Temporal Expression has an event in the given date range and if so, return the first occurrence
  # Default values span up a range of one year
  def calc_next_date(expr, start_date = Date.today, end_date = Date.today + 365)

    start_expr = Runt::PDate.day(start_date.year, start_date.month, start_date.day)
    end_expr = Runt::PDate.day(end_date.year, end_date.month, end_date.day)

    range = Runt::DateRange.new(start_expr, end_expr)

    next_date = expr.dates(range, 1) # next_date is actually an array with one element of Runt::PDate

    return next_date

  end

end

