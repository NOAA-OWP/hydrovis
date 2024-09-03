# Common Errors:

## NoDownstreamLID Error

If there is no downstream RFC point detected, we cannot determine how far to route the flow

<img src="photos/error_example_1.png" alt="isolated" width="750"/>

## NoForecastError

If there is an Empty NWPS response, we can't route flow

<img src="photos/error_example_2.png" alt="isolated" width="750"/>

## LID not detected

Since we are using a mock database with only 170/3000+ RFC points, it is very common for a downstream RFC point to not be included in the mock database. Thus, when running RnR with docker compose you will often see a PydanticValidationError for LID not detected (there being a None where there should be rfc downstream data)

