class_name EdgegapSettings
extends RefCounted

## Edgegap matchmaker settings for the FIND MATCH tab.
## Copy the API URL and Auth Token from the dashboard (Matchmaker → your matchmaker).
## The Auth Token is the matchmaker's client token: it is meant to ship in game
## clients and grants no access to the Edgegap account. Never put the Edgegap API
## token here.
## EDGEGAP_MATCHMAKER_URL / EDGEGAP_MATCHMAKER_TOKEN env vars override these.

const MATCHMAKER_URL := ""
const MATCHMAKER_AUTH_TOKEN := ""
## Profile name in matchmaker-config.json.
const PROFILE := "casual"
## Port name on the app version.
const PORT_NAME := "gameport"
## True when the app version's port has TLS Upgrade on (clients use wss://).
const USE_TLS := true
const POLL_SECONDS := 2.0
## Give up when no server is assigned in this time.
const SEARCH_TIMEOUT_SECONDS := 300.0


static func matchmaker_url() -> String:
	var value := OS.get_environment("EDGEGAP_MATCHMAKER_URL").strip_edges()
	return (value if not value.is_empty() else MATCHMAKER_URL).trim_suffix("/")


static func auth_token() -> String:
	var value := OS.get_environment("EDGEGAP_MATCHMAKER_TOKEN").strip_edges()
	return value if not value.is_empty() else MATCHMAKER_AUTH_TOKEN


static func is_configured() -> bool:
	return not matchmaker_url().is_empty() and not auth_token().is_empty()
