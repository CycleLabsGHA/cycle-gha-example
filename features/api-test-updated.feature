Feature: Updated API Test

Background:
Given I assign "Fight Club" to variable "expectedFClubTitle"
Given I assign "The Fifth Element" to variable "expectedFifthElementTitle"


Scenario: Get first call tmdb endpoint
Given I call api "ApiFiles\tmdb_test_api.api"
    And I assign http response body to variable "responseBody"
When I verify http response had status code 200
    And I assign value from JSON $responseBody with path "/original_title" to variable "originalTitle"
    And I echo $originalTitle
# Then I verify variable $expectedFClubTitle is equal to variable $originalTitle

Scenario: Get Movie Query The Fifth Element tmdb endpoint
Given I call api "ApiFiles\badaboom.api"
    And I assign http response body to variable "responseBody"
    And I echo $responseBody
When I verify http response had status code 200
    And I assign value from JSON $responseBody with path "/results[0]/title" to variable "movieTitle"
    And I echo $movieTitle
# Then I verify variable $expectedFifthElementTitle is equal to variable $movieTitle

Scenario: Testing the XKCD
Given I call api "ApiFiles\xkcd_endpoint.api"
When I assign http response body to variable "responseBody"
And I echo $responseBody
When I verify http response had status code 200
Then I echo "Joke api tested ma dude"

Scenario: Check if Tampa Bay Rays won
Given I call api "ApiFiles\check_rays.api"
    And I assign http response body to variable "responseBody"
    And I echo $responseBody
When I verify http response had status code 200
    And I assign value from JSON $responseBody with path "/events/0/competitions/0/competitors" to variable "competitors"
    And I echo $competitors
    And I assign value from JSON $competitors with path "[?(@.team.displayName=='Tampa Bay Rays')].winner" to variable "raysWinner"
    And I echo $raysWinner
Then I verify that $raysWinner equals "true"
