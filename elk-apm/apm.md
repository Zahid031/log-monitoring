curl -v -X POST "http://localhost:8200/intake/v2/events" \
  -H "Content-Type: application/x-ndjson" \
  -d $'{"metadata":{"service":{"name":"test-service","agent":{"name":"curl","version":"1.0"}}}}\n{"transaction":{"id":"abc123","trace_id":"xyz123","type":"request","duration":123.4,"result":"success","span_count":{"started":1}}}'

