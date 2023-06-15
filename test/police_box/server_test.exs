defmodule PoliceBox.ServerTest do
  use ExUnit.Case, async: true

  alias PoliceBox.Server

  setup :start

  @localhost {127, 0, 0, 1}

  test "with no backup running", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_not_running())
    assert {:update, false, nil} = MockLights.next_message(mock)
  end

  test "while finding the backup volume", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_finding_volume())
    assert {:update, true, 0.0} = MockLights.next_message(mock)
  end

  test "while mounting the backup volume", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_mounting())
    assert {:update, true, 0.0} = MockLights.next_message(mock)
  end

  test "while preparing source volumes", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_preparing_source())
    assert {:update, true, 0.0} = MockLights.next_message(mock)
  end

  test "while finding changes, fills progress bar", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_finding_changes("1.147749932580161e-05"))
    assert {:update, true, percent} = MockLights.next_message(mock)
    assert_in_delta percent, 1.147749932580161e-06, 0.000000001

    # It's worth 0.1 of the progress bar, so 50% done should be 5% total progress.
    :gen_udp.send(udp, {@localhost, port}, tmutil_finding_changes("0.5"))
    assert {:update, true, 0.05} = MockLights.next_message(mock)

    # 100% done should be 10% total progress.
    # Note that 100% progress is represented by the integer 1,
    # rather than a float string.
    :gen_udp.send(udp, {@localhost, port}, tmutil_finding_changes(1))
    assert {:update, true, 0.1} = MockLights.next_message(mock)
  end

  test "while copying, fills progress bar", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_copying("0.0004930557076571144"))
    assert {:update, true, percent} = MockLights.next_message(mock)
    assert_in_delta percent, 0.1004437, 0.000001

    # It's worth 0.9 of the progress bar, starting at 0.1, 
    # so 50% done should be 55% total progress.
    :gen_udp.send(udp, {@localhost, port}, tmutil_copying("0.5"))
    assert {:update, true, 0.55} = MockLights.next_message(mock)

    # 100% done should be 100% total progress.
    # I've not actually seen whether this is represented as "1.0" or just 1,
    # but it shouldn't matter either way.
    :gen_udp.send(udp, {@localhost, port}, tmutil_copying(1))
    assert {:update, true, 1.0} = MockLights.next_message(mock)
  end

  test "while thinning after backup", %{mock: mock, port: port, udp: udp} do
    :gen_udp.send(udp, {@localhost, port}, tmutil_thinning())
    assert {:update, true, 1.0} = MockLights.next_message(mock)
  end

  defp start(_ctx) do
    {:ok, mock} = start_supervised(MockLights)
    {:ok, pid} = start_supervised({Server, port: 0})
    {:ok, port} = Server.port(pid)
    {:ok, udp} = :gen_udp.open(0)
    [mock: mock, pid: pid, port: port, udp: udp]
  end

  defp tmutil_not_running do
    """
    Backup session status:
    {
        ClientID = "com.apple.backupd";
        Percent = "-1";
        Running = 0;
    }
    """
  end

  defp tmutil_finding_volume do
    """
    Backup session status:
    {
        BackupPhase = FindingBackupVol;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:00:05 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        Percent = "-1";
        Running = 1;
        Stopping = 0;
    }
    """
  end

  defp tmutil_mounting do
    """
    Backup session status:
    {
        BackupPhase = MountingBackupVol;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:00:06 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        Percent = "-1";
        Running = 1;
        Stopping = 0;
    }
    """
  end

  defp tmutil_preparing_source do
    """
    Backup session status:
    {
        BackupPhase = PreparingSourceVolumes;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:00:28 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        DestinationMountPoint = "/Volumes/Backups of mello";
        Percent = "-1";
        Running = 1;
        Stopping = 0;
    }
    """
  end

  defp tmutil_finding_changes(fraction_done) do
    """
    Backup session status:
    {
        BackupPhase = FindingChanges;
        ChangedItemCount = 1;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:00:36 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        DestinationMountPoint = "/Volumes/Backups of mello";
        FractionDone = #{inspect(fraction_done)};
        FractionOfProgressBar = "0.1";
        Running = 1;
        Stopping = 0;
        sizingFreePreflight = 1;
    }
    """
  end

  defp tmutil_copying(percent) do
    # Note that the bytes, files, time remaining, etc, won't make much sense
    # in relation to the percent, but we don't care about those anyway.
    """
    Backup session status:
    {
        BackupPhase = Copying;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:07:32 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        DestinationMountPoint = "/Volumes/Backups of mello";
        FractionOfProgressBar = "0.9";
        Progress =     {
            Percent = #{percent};
            TimeRemaining = "289.5220736100292";
            "_raw_Percent" = #{percent};
            "_raw_totalBytes" = 681286971392;
            bytes = 952909824;
            files = 2055;
            sizingFreePreflight = 1;
            totalBytes = 681286971392;
            totalFiles = 4149729;
        };
        Running = 1;
        Stopping = 0;
    }
    """
  end

  defp tmutil_thinning do
    # This sometimes happens at the start of the backup, in addition to the end.
    # If that bugs me too much, I'll start having it inherit the prior progress.
    """
    Backup session status:
    {
        BackupPhase = ThinningPostBackup;
        ClientID = "com.apple.backupd";
        DateOfStateChange = "2023-06-15 18:12:09 +0000";
        DestinationID = "1EA09FA6-52FD-4EE6-842B-C7F8AA7D71CF";
        DestinationMountPoint = "/Volumes/Backups of mello";
        Percent = "-1";
        Running = 1;
        Stopping = 0;
    }
    """
  end
end
