require IEx
require Logger
require Poison
require Ecto.Query
alias Iphod.Repo
alias Iphod.Chat
# alias Iphod.Reflection

defmodule Iphod.IphodChannel do
  import Iphod.Mailer
  use Iphod.Web, :channel
  # import SundayReading
  # import DailyReading
  # import Psalms
  # import Lityear
  # import EsvText
  use Timex
  @tz "America/Los_Angeles"
  @email %{ from: "", topic: "", text: ""}
#  @config %{ ot: "ESV",
#             ps: "Coverdale",
#             nt: "ESV",
#             gs: "ESV",
#             fnotes: "fnotes"
#            }


#  alias Saints.Donor


  def join("iphod:readings", payload, socket) do
    if authorized?(payload) do
      # send self(), :after_join
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in(request, params, socket) do
    # IO.puts ">>>>> #{request}, #{inspect params}"
    response = handle_request(request, params, socket)
    response
  end

  def handle_request("ping", arg, socket) do
    IO.puts ">>>>>PING: #{inspect arg}"
    {:noreply, socket}
  end

  def handle_request("init_calendar", _, socket) do
    push socket, "init_email", @email
    {:noreply, socket}  
  end

  def handle_request("get_prayer_reading", [_section, _version, ""], socket) do
    {:noreply, socket}
  end

  def handle_request("get_prayer_reading", [section, version, vss], socket) do
    vss 
      |> String.split(", ")
      |> Enum.map( fn(lesson) ->
        resp = BibleText.selection(lesson, version, section)
        push socket, "alt_lesson", %{resp: resp}
      end)
    {:noreply, socket}
  end

  def handle_request("get_alt_reading", [section, version, vss], socket) do
    resp = BibleText.selection(vss, version, section)
    push socket, "alt_lesson", %{resp: resp}
    {:noreply, socket}
  end

  def handle_request("get_single_reading", [vss, version, service, section], socket) do
    # resp should contain 
    #  [:collect, :colors, :date, :gs, :nt, :ofType, :ot, :ps, :season, :show, :title,
    #  :week]
    resp = BibleText.selection( vss, version, service)
    push socket, "single_lesson", %{resp: resp}
    {:noreply, socket}
  end

  def handle_request("get_text", ["nil" | _t], socket) do
    # IO.puts ">>>>> NIL REQUEST"
    {:noreply, socket}
  end

  def handle_request("get_text", ["Reflection", tail], socket) do
    # IO.puts ">>>>> BAD GET REFLECTION"
    {:noreply, socket}
  end

  def handle_request("get_text", ["Reflection", date, _versions], socket) do
    day = date |> String.split(" ", [parts: 2, trim: 2]) |> List.last
    resp = Repo.one(from r in Iphod.Reflection, where: [date: ^day, published: true], select: {r.author, r.markdown})
    {author, markdown} = if resp, do: resp, else: {"", "Sorry, nothing today"}
    push socket, "reflection_today", %{author: author, markdown: markdown}
    {:noreply, socket}
  end

  def handle_request("get_text", ["NextSunday", date, versions], socket) do
    nextSunday = text_to_date(date) |> Lityear.date_next_sunday
    push socket, "eu_today", SundayReading.eu_body(nextSunday, versions_map(:eu, versions))
    {:noreply, socket}  
  end

  def handle_request("get_text", ["EU", date, versions], socket) do
    # a couple things need to be done here
    # 1) is the date a redletter day or not
    # 2) are footnotes to be displayed or not
    day = text_to_date date
    # IO.puts inspect(SundayReading.eu_body(day))
    push socket, "eu_today", SundayReading.eu_body(day, versions_map(:eu, versions))
    {:noreply, socket}  
  end

  def handle_request("get_text", ["MP", date, versions], socket) do
    day = text_to_date date
    push socket, "mp_today", DailyReading.mp_body(day, versions_map(:mp, versions))
    {:noreply, socket}  
  end
  
  def handle_request("get_text", ["EP", date, versions], socket) do
    day = text_to_date date
    push socket, "ep_today", DailyReading.ep_body(day, versions_map(:ep, versions))
    {:noreply, socket}  
  end

  def handle_request("get_text", date, socket) do
    handle_request("get_text", ["Reflection", date], socket)
    handle_request("get_text", ["EU", date], socket)
    handle_request("get_text", ["MP", date], socket)
    handle_request("get_text", ["EP", date], socket)
  end

  def handle_request("lessons_now", args, socket) do
    # IEx.pry
    {:noreply, socket}
  end
  
  def handle_request("get_lesson", [section, versions, vss], socket) when section in ~w(mp1 mp2 mpp ep1 ep2 epp) do
    ver = use_version(section, versions)
    resp = BibleText.selection( vss, ver, section)
    push socket, "single_lesson", %{resp: resp}
    {:noreply, socket}
  end

  def handle_request("get_lesson", [section, versions, vss], socket) when section in ~w(ot ps nt gs) do
    ver = use_version(section, versions)
    resp = BibleText.selection( vss, ver, section)
    push socket, "single_lesson", %{resp: resp}
    {:noreply, socket}
  end

  def handle_request("get_lesson", [_section, _versions, _date], socket) do
    {:noreply, socket}
  end

  def handle_request("request_send_email", email, socket) do
    send_contact_me email["from"], email["topic"], email["text"]
    push socket, "new_email", @email
    {:noreply, socket}
  end



def handle_request("get_chat", _bool, socket) do
  limit = 30
  resp = Repo.all from c in Chat, [order_by: [desc: :inserted_at], limit: ^limit]
  chats = resp |> Enum.map( &( "#{&1.text} <p class='whowhen'>#{&1.user} at #{&1.inserted_at}</p>"))
  shout = %{  section: "",
              text: "",
              time: "",
              user: "",
              showChat: true,
              chat: chats,
              comment: ""
            }
  push socket, "latest_chats", shout
  {:noreply, socket}
end

  def handle_request("shout", payload, socket) do
    thisChat = %Chat{ section:  (if payload |> (Map.has_key? "section"), do: payload["section"], else: "lobby"),
                  text:     payload["text"],
                  user:     payload["user"]
                }
    case Repo.insert( 
      %Chat{  section:  (if payload |> (Map.has_key? "section"), do: payload["section"], else: "lobby"),
              text:     payload["text"],
              user:     payload["user"]
            }) do
      {:ok, user} -> 
        broadcast socket, "shout", payload
      {:error, changeset} ->
        push socket, "submitted", %{resp: "error"}
    end
    {:noreply, socket}
  end

  # This is invoked every time a notification is being broadcast
  # to the client. The default implementation is just to push it
  # downstream but one could filter or change the event.
  def handle_out(_event, _payload, socket) do
    {:noreply, socket}
  end

  def versions_map(:eu, [ps, ot, nt, gs]), do: %{ps: ps, ot: ot, nt: nt, gs: gs}
  def versions_map(:mp, [ps, ot, nt, gs]), do: %{mpp: ps, mp1: ot, mp2: nt}
  def versions_map(:ep, [ps, ot, nt, gs]), do: %{epp: ps, ep1: nt, ep2: gs}

  def use_version(section, versions) when versions |> is_list do
    case section do
      "ot"  -> versions_map(:eu, versions).ot
      "ps"  -> versions_map(:eu, versions).ps
      "nt"  -> versions_map(:eu, versions).nt
      "gs"  -> versions_map(:eu, versions).gs
      "mpp" -> versions_map(:eu, versions).ps
      "mp1" -> versions_map(:eu, versions).ot
      "mp2" -> versions_map(:eu, versions).nt
      "epp" -> versions_map(:eu, versions).ps
      "ep1" -> versions_map(:eu, versions).nt
      "ep2" -> versions_map(:eu, versions).gs
      _  -> "ESV"
    end
  end

  def use_version(section, version), do: version

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end

  def text_to_date(s) do
    {ok, date} = Timex.parse(s, "{WDfull} {Mfull} {D}, {YYYY}")
    {ok, date} = if ok == :error, 
      do: Timex.parse(s, "{WDshort} {Mshort} {D} {YYYY}"), 
      else: {ok, date}
    {ok, date} = if ok == :error,
      do: Timex.parse(s, "{0M}/{0D}/{YYYY}"),
      else: {ok, date}
    Timex.to_date date
  end
end
