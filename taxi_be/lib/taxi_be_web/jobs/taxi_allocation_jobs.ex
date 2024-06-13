defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])
    {:ok, %{request: request, status: :not_accepted}}
  end

  def handle_info(:step1, %{request: request, status: :not_accepted} = state) do

    # send customer ride fare
    task = Task.async(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)
    Task.await(task)

    # get all taxis
    candidate_taxis = select_candidate_taxis(request)

    %{"booking_id" => booking_id} = request

    # send out requests to all taxis
    Enum.map(candidate_taxis, fn taxi ->
      TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{mensaje: "viaje disponible", bookingId: booking_id})
    end)

    # repeat immediate process
    Process.send_after(self(), :timelimit, 20000)
    {:noreply, Map.put(state, :time, :good)}
  end

  def handle_info(:timelimit, %{request: request, status: :not_accepted} = state) do
    %{"username" => customer} = request
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{mensaje: "Hubo un problema con el viaje"})
    {:noreply, %{state | time: :exceeded}}
  end

  def handle_info(:timelimit, %{status: :accepted} = state) do
    {:noreply, %{state | time: :exceeded}}
  end

  def handle_cast({:process_accept, driver_username}, %{request: request, status: :not_accepted, time: :good} = state) do
    %{"username" => customer, "pickup_address" => pickup_address} = request

    # acá agarro a todos los conductores
    candidate_taxis = select_candidate_taxis(request)

    # acá agarro el que aceptó
    selected_taxi = Enum.find(candidate_taxis, fn taxi -> taxi.nickname == driver_username end)

    # calculamos el tiempo estimado, acá chido
    estimated_arrival = calculaTiempo(pickup_address, selected_taxi)

    IO.inspect(estimated_arrival, label: "Llega más o menos en")

    # la función nos da el tiempo en segundos, por lo q hay que hacer cuentas
    estimated_minutes = round(Float.floor(estimated_arrival / 60, 0))
    estimated_seconds = rem(round(estimated_arrival), 60)

    message = "El conductor #{driver_username} llegará en #{estimated_minutes} minutos y #{estimated_seconds} segundos"

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{mensaje: message})

    {:noreply, %{state | status: :accepted}}
  end

  def handle_cast({:process_accept, driver_username}, %{status: :accepted} = state) do
    TaxiBeWeb.Endpoint.broadcast("driver:" <> driver_username, "booking_notification", %{mensaje: "Viaje aceptado por alguien más"})
    {:noreply, state}
  end

  def handle_cast({:process_accept, driver_username}, %{status: :not_accepted, time: :exceeded} = state) do
    TaxiBeWeb.Endpoint.broadcast("driver:" <> driver_username, "booking_notification", %{mensaje: "Aceptacion demasiada tarde"})
    {:noreply, state}
  end

  def handle_cast({:process_reject, _}, state) do
    {:noreply, state}
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
     } = request

    coord1 = TaxiBeWeb.Geolocator.geocode(pickup_address)
    coord2 = TaxiBeWeb.Geolocator.geocode(dropoff_address)
    {distance, _duration} = TaxiBeWeb.Geolocator.distance_and_duration(coord1, coord2)
    {request, Float.ceil(distance/80)}
  end

  def calculaTiempo(pickup_address, taxi) do
    taxi_coords = {:ok, [taxi.longitude, taxi.latitude]}
    pickup_coords = TaxiBeWeb.Geolocator.geocode(pickup_address)

    # agarramos la función de geolocator de distancia y duración, y pues no queremos distancia vdd
    {_distance, duration} = TaxiBeWeb.Geolocator.distance_and_duration(taxi_coords, pickup_coords)
    duration
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request
   TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{mensaje: "Ride fare: #{fare}"})
  end

  def select_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "equidelol", latitude: 19.0319783, longitude: -98.2349368}, # Angelopolis
      %{nickname: "alekong", latitude: 19.0061167, longitude: -98.2697737}, # Arcangeles
      %{nickname: "alonsense", latitude: 19.0092933, longitude: -98.2473716} # Paseo Destino
    ]
  end

end
