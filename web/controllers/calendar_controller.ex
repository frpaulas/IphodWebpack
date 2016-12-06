require IEx
defmodule Iphod.CalendarController do
  use Iphod.Web, :controller
  use Timex
  import Iphod.IphodChannel

  def index(conn, params) do
    select_language params
    # render_calendar conn, Date.now, nil
    render_calendar conn, get_month(Date.now), nil
  end

  def mindex(conn, params) do
    select_language params
    # render_calendar conn, Date.now, "min"
    render_calendar conn, get_month(Date.now), "min"
  end

  def prev(conn, params) do
    select_language params
    date = params_to_date(params, -1)
    # render_calendar conn, date, params["min"]
    render_calendar conn, get_month(date), params["min"]
  end

  def next(conn, params) do
    select_language params
    date = params_to_date(params, 1)
    # render_calendar conn, date, params["min"]
    render_calendar conn, get_month(date), params["min"]
  end

  def season(conn, params) do
    # something like `get_month next_season("advent", Date.now)`
    # and get the calendar month for the beginning of advent
    # this_month = get_month(Lityear.next_season(params["season"], Date.now))
    select_language params
    this_month = Lityear.next_season(params["season"], Date.now)
    # render_calendar conn, this_month, params["min"]
    render_calendar conn, get_month(this_month), params["min"]
  end

  def eu(conn, params), do: readings_for(conn, params, "EU")
  def mp(conn, params), do: readings_for(conn, params, "MP")
  def ep(conn, params), do: readings_for(conn, params, "EP")

  def readings_for(conn, params, service) do
    this_date = params["month"] <> "/" <> params["day"] <> "/" <> params["year"]
    # render_calendar_readings conn, Date.now, this_date, params["service"], nil
    render_calendar conn, get_month(Date.now, service, this_date), params["min"]    
  end

# HELPERS

  def select_language(params) do
    unless params["locale"], do: Gettext.put_locale Iphod.Gettext, "en"
  end

  def params_to_date(params, shift) do
    Date.from(
      { params["year"] |>String.to_integer, 
        params["month"] |> Timex.month_to_num,
        1
      }) |> Date.shift(months: shift)
  end

  def render_calendar(conn, model, min \\ nil) do
    {layout, view} = if min, do: {"app.html", "mindex.html"}, else: {"desktop_app.html", "index.html"}
    conn
      |> put_layout(layout)
      |> render(view, model: model)
  end

  def get_month(date, service \\ "nil", this_date \\ "nil") do
    days = list_of_weeks_from begin_month(date), end_month(date)
    %{  calendar: days,
        month:    date |> Timex.format!("{Mfull}"),
        year:     date |> Timex.format!("{YYYY}"),
        service:  service,
        date:     this_date
    }
  end

  def begin_month(date) do
    bom = date |> Timex.beginning_of_month
    bwk = bom |> Timex.days_to_beginning_of_week(7)
    Timex.shift bom, days: -bwk
  end

  def end_month(date) do
    bem = date |> Timex.end_of_month
    ewk = bem |> Timex.days_to_end_of_week(7)
    Timex.shift bem, days: ewk
  end

  def list_of_weeks_from(start_date, end_date) do
    _list_of_weeks_from start_date, end_date, 1, [ [] ]
  end

  def _list_of_weeks_from(start_date, end_date, 8, [head|list]) do
    new_head = Enum.reverse head
    if start_date |> Timex.before?(end_date) do
      _list_of_weeks_from(start_date, end_date, 1, [ [] | [%{days: new_head}|list] ])
    else
      [%{days: new_head}|list] |> Enum.reverse
    end
  end

  def _list_of_weeks_from(start_date, end_date, n, [head|list]) do
    day = %{  date: start_date |> Timex.format!("{WDfull} {Mfull} {D}, {YYYY}"),
              id: start_date |> Timex.format!("{WDfull}{Mfull}{D}_{YYYY}"),
              name: start_date |> Timex.format!("{WDfull}"),
              dayOfMonth: start_date |> Timex.format!("{D}"),
              colors: DailyReading.color_for(start_date),
              title: DailyReading.title_for(start_date),
              mp_reading: DailyReading.reading_map("mp", start_date),
              ep_reading: DailyReading.reading_map("ep", start_date),
              eu_reading: SundayReading.reading_map(start_date),
              today: start_date == Date.now
          }
    new_head = [day | head]
    new_date = start_date |> Timex.shift(days: 1)
    _list_of_weeks_from(new_date, end_date, n+1, [new_head|list])
  end

end
