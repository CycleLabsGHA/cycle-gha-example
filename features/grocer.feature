Feature: Grocer IO Loop

Background:
When "I stagger the start times of each worker"
And "I stage test data to add a new order"
Then I open "Chrome" web browser
#Then I open "Chrome" web browser on remote "http://localhost:4444"

After Scenario:
When I close web browser

Scenario: Embedded Datastore Stress Test
When I assign 1 to variable "loop_count"
While I verify number $loop_count is less than or equal to 2
	Given "I am logged into the Grocer IO site"
	And "the Orders page is displayed"
	When "I click the Add Order button"
	And "I enter valid new order information"
	And "I click the Add button on the Add New Order window"
	Then "the newly added order appears in the order list on the Order page"
	And "I logout of Grocer IO"
	And I increase variable "loop_count" by 1
EndWhile

@wip
Scenario: I stagger the start times of each worker
	If I verify variable "start_delay" is assigned
		Then I convert string variable "start_delay" to INTEGER variable "start_delay"
		And I multiply variable "start_delay" by 5
		And I wait $start_delay seconds
	EndIf

###################################################
# Source:                                         #
# https://github.com/cycle-labs/grocer-io-example #
###################################################
@wip
Scenario: I stage test data to add a new order
	When I "load variables from the Group Test CSV"
		When I assign all chevron variables to dollar variables
	
	When I "assign my test suite data"
		When I assign 10 to variable "max_response"
		And I assign 1 to variable "step_delay"

	When I "assign my credentials data"
		If I verify variable "user_id" is assigned
		Else I "assign default values to worker variables"
			When I assign "courtney.montgomery@cyclelabs.io" to variable "user_id"
			And I assign "hunter13" to variable "password"
		EndIf
	
	When I "assign my customer data"
		When I assign "Elvis Presley" to variable "customer_name"
		And I assign 9001 to variable "order_number"
		And I assign "$350.00" to variable "price"

@wip
Scenario: I am logged into the Grocer IO site
	Given I "have navigated to the site's login page"
		When I navigate to "https://cyclelabs.io/playground" in web browser
		And I see element "text:Email" in web browser within $max_response seconds

	When I "enter my credentials and login"
		When I type $user_id in element "name:email_login" in web browser within $max_response seconds
		And I wait $step_delay seconds
		And I type $password in element "xPath://input[@type='password']" in web browser within $max_response seconds
		And I wait $step_delay seconds
		And I click element "text:Login" in web browser
		And I wait $step_delay seconds
		Once I do not see element "text:Login" in web browser

@wip
Scenario: the Orders page is displayed 
	Then I see element "text:Orders" in web browser within $max_response seconds

@wip
Scenario: I click the Add Order button
	When I click element "text:Add order" in web browser within $max_response seconds
	And I wait $step_delay seconds
	Once I see "Add new order" in web browser

@wip
Scenario: I enter valid new order information
	When I type $customer_name in element "name:order_customer" in web browser within $max_response seconds
	And I wait $step_delay seconds
	And I type $order_number in element "name:order_number" in web browser within $max_response seconds
	And I wait $step_delay seconds
	And I type $price in element "name:order_price" in web browser within $max_response seconds
	And I wait $step_delay seconds

@wip
Scenario: I click the Add button on the Add New Order window
	When I click element "xPath://button[text()='Add']" in web browser within $max_response seconds
	And I wait $step_delay seconds
	Once I do not see element "xPath://button[text()='Add']" in web browser
	
@wip
Scenario: the newly added order appears in the order list on the Order page
	Then I see $order_number in web browser within $max_response seconds
	And I see $customer_name in web browser within $max_response seconds
	And I see $price in web browser within $max_response seconds

@wip
Scenario: I logout of Grocer IO
	When I click element "className:user" in web browser within $max_response seconds
	And I wait $step_delay seconds
	And I click element "text:Logout" in web browser within $max_response seconds
	And I wait $step_delay seconds
	And I see element "text:Email" in web browser within $max_response seconds
