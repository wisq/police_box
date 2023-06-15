defmodule PoliceBox do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(app_children(), strategy: :one_for_one)
  end

  defp app_children do
    case Application.get_env(:police_box, :start, true) do
      true -> [PoliceBox.Server, PoliceBox.Lights]
      false -> []
    end
  end
end
