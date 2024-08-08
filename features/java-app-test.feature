Feature: Java App Steps

Background: Setup Starting State
	Given I assign values from config file "data/locators/Java App Locators/Java App Locators.conf" to variables
	Given I open java app "app" from jar file "javaapptestbed_2.12-0.1.0-SNAPSHOT.jar"
    Given I assign "5" to variable "wait_med"
    Given I wait $wait_med seconds

After Scenario: Close Java App
	If I close java app
	endif

Scenario: Java App Steps
    Given I see object "cssSelector:label[text = 'Power Off']" in java app
    And I do not see object "cssSelector:label[text = 'Now with Power']" in java app
    Then I click object "cssSelector:button[text = 'Click Me']" in java app
    And I assign "cssSelector:label[text = 'Now with Power']" to variable "with_power_locator"
    And I do not see object $with_power_locator in java app
    And I see object $with_power_locator in java app within 10 seconds
    And I do not see object "cssSelector:label[text = 'Power Off']" in java app

# These scenarios fail on remote agents with java keymapping conflict
# Scenario: Java App Import Config Locators - triple quotes
# 	Given I type USERNAME from credentials "Testme" in object $cssSelectortextfieldInputUsername in java app within $wait_med seconds
# 	When I type PASSWORD from credentials "Testme" in object $cssSelectortextfieldInputPassword in java app within $wait_med seconds
#   Then I see value "testme" equals text in object $cssSelectortextfieldInputUsername in java app

# Scenario: Java App In-Block Locators - triple quotes
# 	Given I type USERNAME from credentials "Testme" in object """cssSelector:label[text = 'Username:'] + text-field""" in java app within $wait_med seconds
# 	When I type PASSWORD from credentials "Testme" in object """cssSelector:label[text = 'Password:'] + password-field""" in java app within $wait_med seconds
#     Then I see value "testme" equals text in object $cssSelectortextfieldInputUsername in java app