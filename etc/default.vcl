#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and https://www.varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import std;

# Allow any local IP address to invalidate the cache.
acl local {
    "10.0.0.0"/8;
    "172.16.0.0"/12;
    "192.168.0.0"/16;
}

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "backend";
    .port = "80";
}

sub vcl_hash {
    # A different response is delivered based on the forwarded proto.
    if (req.http.X-Forwarded-Proto) {
      hash_data(req.http.X-Forwarded-Proto);
    }

    # Cf-Visitor will be either `http` or `https`
    # @see https://support.cloudflare.com/hc/en-us/articles/200170986-How-does-Cloudflare-handle-HTTP-Request-headers
    if (req.http.CF-Visitor) {
      hash_data(req.http.CF-Visitor);
    }
}

sub vcl_recv {
    if (req.http.Cookie) {
      # Remove has_js and Google Analytics __* cookies.
      set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");
      # Remove a ";" prefix, if present.
      set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

      # Remove WordPress cookies.
      set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-\d+=[^;]+(; )?", "");
      set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-time-\d+=[^;]+(; )?", "");
      set req.http.Cookie = regsuball(req.http.Cookie, "wordpress_test_cookie=[^;]+(; )?", "");

      # Unset an empty Cookie header.
      if (req.http.Cookie == "") {
        unset req.http.Cookie;
      }
    }

    # Drupal & API Platform: Purge By Cache-Tags
    if (req.method == "BAN") {
      # Only allow BAN requests from local IP addresses.
      if (!client.ip ~ local) {
        return (synth(403, "Not allowed."));
      }

      # Logic for the ban, using the X-Cache-Tags header.
      if (req.http.Purge-Cache-Tags) {
        ban("obj.http.Purge-Cache-Tags ~ " + req.http.Purge-Cache-Tags);
      }
      elseif (req.http.ApiPlatform-Ban-Regex) {
        ban("obj.http.Cache-Tags ~ " + req.http.ApiPlatform-Ban-Regex);
      }
      else {
        return (synth(403, "Purge-Cache-Tags header missing."));
      }

      # Throw a synthetic page so the request won't go to the backend.
      return (synth(200, "Banned"));
    }

    # WordPress: Purge by URL (or regex)
    if (req.method == "PURGE") {
      # Same ACL check as above:
      if (!client.ip ~ local) {
        return (synth(403, "Not allowed."));
      }

      if (req.http.X-Purge-Method == "regex") {
        ban("req.url ~ " + req.url + " && req.http.host ~ " + req.http.host);
        return (synth(200, "Purged"));
      }

      return (purge);
    }
}

sub vcl_backend_response {
  # 403 requests are not cached, so override the status for a moment.
  if (beresp.status == 403) {
    set beresp.http.X-Status = beresp.status;
    set beresp.status = 200;
  }
  if (!bereq.uncacheable) {
    set beresp.http.X-Cahce-Control = beresp.http.Cache-Control;
    unset beresp.http.Cache-Control;
  }
}

sub vcl_deliver {
    # Reset the status of 403 requests.
    if (resp.http.X-Status) {
      set resp.status = std.integer(resp.http.X-Status, 403);
      unset resp.http.X-Status;
    }

    # Add debugging information.
    if (obj.hits > 0) {
      set resp.http.X-Cache = "HIT";
      set resp.http.X-Cache-Hits = obj.hits;
    }
    else {
      set resp.http.X-Cache = "MISS";
    }
}
