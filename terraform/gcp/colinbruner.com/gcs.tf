###
# colinbruner.com
###

resource "google_storage_bucket" "prod" {
  name     = "colinbruner.com"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  timeouts {}
  #cors {
  #  origin          = ["https://colinbruner.com"]
  #  method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
  #  response_header = ["*"]
  #  max_age_seconds = 3600
  #}
}

###
# staging.colinbruner.com
###

resource "google_storage_bucket" "staging" {
  name     = "staging.colinbruner.com"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  timeouts {}
  #cors {
  #  origin          = ["https://staging.colinbruner.com"]
  #  method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
  #  response_header = ["*"]
  #  max_age_seconds = 3600
  #}
}

###
# develop.colinbruner.com
###

resource "google_storage_bucket" "develop" {
  name     = "develop.colinbruner.com"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  timeouts {}
  #cors {
  #  origin          = ["https://develop.colinbruner.com"]
  #  method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
  #  response_header = ["*"]
  #  max_age_seconds = 3600
  #}
}
