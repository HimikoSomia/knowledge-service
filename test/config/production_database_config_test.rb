require "test_helper"
require "erb"
require "yaml"

class ProductionDatabaseConfigTest < ActiveSupport::TestCase
  DATABASE_NAMES = {
    "primary" => "knowledge_service_production",
    "cache" => "knowledge_service_production_cache",
    "queue" => "knowledge_service_production_queue",
    "cable" => "knowledge_service_production_cable"
  }.freeze

  test "all production roles use the configured host port and credentials" do
    with_database_environment(
      "DB_HOST" => "database.internal",
      "DB_PORT" => "6543",
      "DB_USERNAME" => "production_user",
      "DB_PASSWORD" => "production_password"
    ) do
      production = rendered_database_config.fetch("production")

      DATABASE_NAMES.each do |role, database_name|
        config = production.fetch(role)
        assert_equal database_name, config.fetch("database")
        assert_equal "database.internal", config.fetch("host")
        assert_equal 6543, config.fetch("port")
        assert_equal "production_user", config.fetch("username")
        assert_equal "production_password", config.fetch("password")
      end
    end
  end

  test "production port defaults to 5432" do
    with_database_environment(
      "DB_HOST" => "database.internal",
      "DB_PORT" => nil,
      "DB_USERNAME" => "production_user",
      "DB_PASSWORD" => "production_password"
    ) do
      production = rendered_database_config.fetch("production")

      assert production.values.all? { |config| config.fetch("port") == 5432 }
    end
  end

  test "production host is required while rendering configuration" do
    with_database_environment(
      "DB_HOST" => nil,
      "DB_USERNAME" => "production_user",
      "DB_PASSWORD" => "production_password"
    ) do
      assert_raises(KeyError) { rendered_database_config }
    end
  end

  private

  def rendered_database_config
    source = ERB.new(Rails.root.join("config/database.yml").read).result
    YAML.safe_load(source, aliases: true)
  end

  def with_database_environment(values)
    original = values.to_h { |key, _| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
