defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer
  IO.inspect("Está entrando")

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])
    {:ok, %{request: request, timer: nil, duration: 0, st: Searching, cancel: No_penalty}}
  end

  def handle_info(:step1, %{request: request} = state) do
    # Select a taxi
    {request, _distance, duration} = compute_ride_fare(request)
    task = Task.async(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)

    Task.await(task)

    # Forward request to taxi driver
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    Enum.map(candidate_taxis(), fn taxi ->
      TaxiBeWeb.Endpoint.broadcast(
        "driver:" <> taxi.nickname,
        "booking_request",
        %{
          msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
          bookingId: booking_id
        }
      )
    end)

    timer = Process.send_after(self(), :time_out, 5000)
    {:noreply, %{state | request: request, timer: timer, duration: duration}}
  end

  def handle_info(:time_out, %{request: request, st: Searching} = state) do
    %{"username" => customer} = request
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{msg: "Estamos teniendo problemas para encontrar un taxi, sea paciente"})
    IO.inspect("ya llegue")
    {:noreply, %{state | st: Cancel}}
  end

  def handle_info(:late_cancellation, %{request: _request} = state) do
    IO.inspect("inicia penalizacion")
    {:noreply, %{state | cancel: Penalty}}
  end

  def handle_cast({:handle_accept, _driver_username}, %{request: req, timer: timer, duration: duration, st: Searching} = state) do
    Process.cancel_timer(timer)
    %{"username" => username} = req
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "Su taxi está en camino, llegará en #{Float.ceil(duration / 60)} minutos."})
    timer = Process.send_after(self(), :late_cancellation, 5000)
    {:noreply, %{state | st: Found, timer: timer}}
  end

  def handle_cast({:handle_cancel, _driver_username}, %{request: req, timer: timer, st: Searching} = state) do
    Process.cancel_timer(timer)
    %{"username" => username} = req
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "Se ha cancelado la solicitud de viaje."})
    {:noreply, %{state | st: Cancel}}
  end

  def handle_cast({:handle_cancel, _driver_username}, %{request: req, timer: timer, st: Found, cancel: No_penalty} = state) do
    Process.cancel_timer(timer)
    %{"username" => username} = req
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "Se ha cancelado el viaje."})
    {:noreply, %{state | st: Cancel}}
  end

  def handle_cast({:handle_cancel, _driver_username}, %{request: req, st: Found, cancel: Penalty} = state) do
    %{"username" => username} = req
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "Viaje cancelado, se cobrará una penalización por cancelación tardía."})
    {:noreply, %{state | st: Cancel}}
  end

  def handle_cast({:notify_arrival, driver_username}, %{request: req, st: Found} = state) do
    %{"username" => username} = req
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{msg: "El conductor #{driver_username} ha llegado, su viaje ha comenzado"})
    IO.inspect("llega el taxi")
    {:noreply, %{state | st: Arrived}}
  end

  def handle_cast(_event, state) do
    {:noreply, state}
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request

    coord1 = TaxiBeWeb.Geolocator.geocode(pickup_address)
    coord2 = TaxiBeWeb.Geolocator.geocode(dropoff_address)
    {distance, duration} = TaxiBeWeb.Geolocator.distance_and_duration(coord1, coord2)
    {request, Float.ceil(distance / 300), duration}
  end

  def notify_customer_ride_fare({request, fare, _duration}) do
    %{"username" => customer} = request
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{msg: "Ride fare: #{fare}"})
  end

  def select_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "equidelol", latitude: 19.0319783, longitude: -98.2349368}, # Angelopolis
      %{nickname: "alekong", latitude: 19.0061167, longitude: -98.2697737}, # Arcangeles
      %{nickname: "alonsense", latitude: 19.0092933, longitude: -98.2473716} # Paseo Destino
    ]
  end
  def candidate_taxis() do
    [
      %{nickname: "equidelol", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "alekong", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "alonsense", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
