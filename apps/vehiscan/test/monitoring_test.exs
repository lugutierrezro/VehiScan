defmodule Vehiscan.MonitoringTest do
  use Vehiscan.DataCase, async: true

  alias Vehiscan.Monitoring
  alias Vehiscan.Accounts
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Governance.AuditLog

  setup do
    # 1. Crear Rol
    {:ok, role} =
      Repo.insert(%Accounts.Role{
        name: "operator_test",
        description: "Test Operator",
        permissions: ["view_dashboard", "validate_alerts"],
        access_level: 1
      })

    # 2. Crear Usuario
    {:ok, user} =
      Accounts.create_user(%{
        name: "Test Operator User",
        email: "test_operator@vehiscan.local",
        password: "VehiScan2024!",
        role_id: role.id
      })

    # 3. Crear Cámara
    {:ok, camera} =
      Repo.insert(%Camera{
        code: "TEST-CAM-001",
        type: "fixed",
        location_name: "Calle de Pruebas 123",
        latitude: -12.0463,
        longitude: -77.0427,
        status: "active"
      })

    {:ok, user: user, camera: camera}
  end

  describe "register_alpr_event/1" do
    test "correctly registers capture and normalizes plate", %{camera: camera} do
      attrs = %{
        original_plate: "abc-123-!",
        confidence: 85.5,
        camera_id: camera.id,
        location_name: camera.location_name
      }

      assert {:ok, %{event: event}} = Monitoring.register_alpr_event(attrs)
      assert event.normalized_plate == "ABC123"
      assert event.confidence == 85.5
      assert event.camera_id == camera.id
    end

    test "creates alert if plate matches watchlist", %{camera: camera, user: user} do
      # 1. Agregar placa a watchlist
      {:ok, watchlist_entry} =
        Monitoring.add_to_watchlist(%{
          plate: "XYZ789",
          source: "SAT Test",
          reason: "Vehículo robado",
          severity: "high",
          assigned_by_id: user.id
        })

      # 2. Registrar captura de placa coincidente
      attrs = %{
        original_plate: "xyz-789",
        confidence: 90.0,
        camera_id: camera.id,
        location_name: camera.location_name
      }

      assert {:ok, %{event: event, alerts: [alert]}} = Monitoring.register_alpr_event(attrs)
      assert alert.alpr_event_id == event.id
      assert alert.watchlist_id == watchlist_entry.id
      assert alert.severity == "high"
      assert alert.status == "pending"
    end
  end

  describe "search_events_by_plate/4" do
    test "enforces justification requirement and logs audit", %{user: user, camera: camera} do
      # Registrar evento previo
      Monitoring.register_alpr_event(%{
        original_plate: "AAA999",
        confidence: 88.0,
        camera_id: camera.id,
        location_name: camera.location_name
      })

      # Intento sin justificación (muy corta)
      assert {:error, {:audit_required, changeset}} =
               Monitoring.search_events_by_plate("AAA999", user.id, "Corto", "127.0.0.1")

      assert "La justificación debe tener al menos 10 caracteres" in errors_on(changeset).justification

      # Intento exitoso con justificación adecuada
      assert {:ok, results} =
               Monitoring.search_events_by_plate("AAA999", user.id, "Investigación activa de caso homicidio", "127.0.0.1")

      assert length(results) == 1
      [result] = results
      assert result.normalized_plate == "AAA999"

      # Verificar que se insertó el AuditLog correspondiente
      audit_log = Repo.one(AuditLog)
      assert audit_log.user_id == user.id
      assert audit_log.action == "plate_query"
      assert audit_log.plate_queried == "AAA999"
      assert audit_log.justification == "Investigación activa de caso homicidio"
      assert audit_log.ip_address == "127.0.0.1"
    end
  end

  describe "resolve_alert/3" do
    test "resolves alert and logs operation in AuditLog", %{camera: camera, user: user} do
      # 1. Agregar a watchlist
      {:ok, _watchlist_entry} =
        Monitoring.add_to_watchlist(%{
          plate: "BBB888",
          source: "SAT Test",
          reason: "Embargo",
          severity: "medium",
          assigned_by_id: user.id
        })

      # 2. Captura
      assert {:ok, %{alerts: [alert]}} =
               Monitoring.register_alpr_event(%{
                 original_plate: "BBB888",
                 confidence: 80.0,
                 camera_id: camera.id,
                 location_name: camera.location_name
               })

      # 3. Resolver
      resolve_attrs = %{
        operator_id: user.id,
        validation_details: "Alerta confirmada, auto detenido por operativo policial.",
        status: "validated"
      }

      assert {:ok, resolved} = Monitoring.resolve_alert(alert.id, resolve_attrs, "127.0.0.1")
      assert resolved.status == "validated"
      assert resolved.validation_details == "Alerta confirmada, auto detenido por operativo policial."

      # Verificar logs de auditoría
      # 1. Consulta de agregación (SAT)
      # 2. Operación de alerta
      logs = Repo.all(AuditLog)
      assert Enum.any?(logs, fn log ->
        log.action == "alert_validated" and
        log.user_id == user.id and
        log.filters_applied == %{"alert_id" => alert.id}
      end)
    end
  end
end
