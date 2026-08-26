require "test_helper"

# Prefer Selenium Manager locally so a stale driver earlier in PATH cannot mask
# the driver compatible with the installed browser. Hosted CI provides a matched
# browser and driver pair, and an explicit environment value always wins.
ENV["SE_SKIP_DRIVER_IN_PATH"] ||= "true" unless ENV["CI"]
ENV["SE_AVOID_STATS"] ||= "true"
Selenium::WebDriver.logger.level = :warn

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  browser_mode = ENV["SHOW_BROWSER"] == "1" ? :chrome : :headless_chrome

  driven_by :selenium, using: browser_mode, screen_size: [ 1400, 1400 ]

  private

  def sign_in_through_browser_as(user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_button "Sign in"
    assert_link "Workspaces"
  end
end
