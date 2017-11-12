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
acl invalidators {
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
    if (req.http.X-Forwarded-Proto) {
      hash_data(req.http.X-Forwarded-Proto);
    }
    if (req.http.CF-Visitor) {
      hash_data(req.http.CF-Visitor);
    }
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.

    if (req.http.Cookie) {
      # Remove has_js and Google Analytics __* cookies.
      set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");
      # Remove a ";" prefix, if present.
      set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

      # Unset an empty Cookie header.
      if (req.http.Cookie == "") {
        unset req.http.Cookie;
      }
    }

    # Only allow BAN requests from IP addresses in the 'purge' ACL.
    if (req.method == "BAN") {
      # Same ACL check as above:
      if (!client.ip ~ invalidators) {
        return (synth(403, "Not allowed."));
      }

      # Logic for the ban, using the X-Cache-Tags header.
      if (req.http.Purge-Cache-Tags) {
        ban("obj.http.Purge-Cache-Tags ~ " + req.http.Purge-Cache-Tags);
      }
      else {
        return (synth(403, "Purge-Cache-Tags header missing."));
      }

    # Throw a synthetic page so the request won't go to the backend.
    return (synth(200, "Banned"));
  }
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.
  if (beresp.status == 403) {
    set beresp.http.X-Status = beresp.status;
    set beresp.status = 200;
  }
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.
    if (resp.http.X-Status) {
      set resp.status = std.integer(resp.http.X-Status, 403);
      unset resp.http.X-Status;
    }
    if (obj.hits > 0) {
      set resp.http.X-Cache = "HIT";
      set resp.http.X-Cache-Hits = obj.hits;
    }
    else {
      set resp.http.X-Cache = "MISS";
    }
}
