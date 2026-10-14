"""Stateful mock of the Ahamatic endpoints used by the `translation` tool.

Usage: python3 mock_ahamatic.py <state.json>

Listens on a free port on 127.0.0.1 and prints it on the first stdout line.
Behaves like aha-api where the script depends on it:
  - `authorization` must be the token (`Bearer ` optional), otherwise 401.
  - GET /api/e/<entity> parses `filter[X]` / `fields[]` like `qs`; reference
    fields of _translations come back populated; unknown entities return [].
  - POST /api/e/<entity> answers {message, content: {Id, ...}}; references
    must be numeric Ids that exist (422 otherwise).

Test helpers:
  POST /__reset   body: a full state, or empty to reload <state.json>
  GET  /__log     every request received since the last reset
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, unquote, urlparse

FIXTURE = sys.argv[1]


def load_fixture():
    with open(FIXTURE, encoding='utf-8') as f:
        return json.load(f)


state = load_fixture()
log = []


def next_id(rows):
    return max([r['Id'] for r in rows] + [state.get('firstNewId', 1000) - 1]) + 1


def collection(entity):
    return {
        'AppLanguages': state['languages'],
        '_translations': state['translations'],
        state['keyEntity']: state['keys'],
    }.get(entity)


def populate_translation(t):
    key = next((k for k in state['keys'] if k['Id'] == t.get('Key')), None)
    language = next((l for l in state['languages'] if l['Id'] == t.get('Language')), None)
    return {**t, 'Key': key, 'Language': language}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length) if length else b''
        return json.loads(raw) if raw.strip() else None

    def handle_request(self, method):
        global state, log
        url = urlparse(self.path)
        query = parse_qsl(url.query, keep_blank_values=True)
        body = self.read_body() if method in ('POST', 'PUT') else None

        if url.path == '/__reset':
            state = body if body else load_fixture()
            log = []
            return self.reply(200, {})
        if url.path == '/__log':
            return self.reply(200, log)

        log.append({
            'method': method,
            'path': url.path,
            'query': query,
            'body': body,
            'authorization': self.headers.get('authorization'),
        })

        if method == 'POST' and url.path == '/api/auth/email':
            credentials = state['credentials']
            if (body or {}).get('apiKey') != credentials['apiKey'] or \
                    body.get('emailAddress') != credentials['email'] or \
                    body.get('password') != credentials['password']:
                return self.reply(401, {'message': 'Invalid credentials.'})
            return self.reply(200, {
                'token': state['token'],
                'application': {'Id': 1, 'SchemaName': state['schemaName']},
            })

        token = (self.headers.get('authorization') or '').removeprefix('Bearer ')
        if token != state['token']:
            return self.reply(401, {'message': 'Failed to authenticate token'})

        parts = [unquote(p) for p in url.path.split('/') if p]

        # GET /api/entities/<entity>?collection=<SchemaName>
        if method == 'GET' and parts[:2] == ['api', 'entities'] and len(parts) == 3:
            schema = state['schemas'].get(parts[2])
            if dict(query).get('collection') != state['schemaName'] or schema is None:
                return self.reply(200, {'lists': []})
            return self.reply(200, {'lists': [{'Id': parts[2], 'Schema': json.dumps(schema)}]})

        if parts[:2] != ['api', 'e'] or len(parts) < 3:
            return self.reply(404, {'message': 'Not found'})
        entity = parts[2]
        rows = collection(entity)

        if method == 'GET':
            if [v for k, v in query if k == 'fields'] and len([k for k, _ in query if k == 'fields']) == 1:
                return self.reply(412, {'message': 'fields.filter is not a function'})
            filters = {k[len('filter['):-1]: v for k, v in query if k.startswith('filter[')}
            data = [r for r in rows or [] if all(str(r.get(k)) == v for k, v in filters.items())]
            if entity == '_translations':
                data = [populate_translation(t) for t in data]
            return self.reply(200, {'data': data})

        if rows is None:
            return self.reply(412, {'message': f'Unknown entity {entity}'})

        if method == 'POST' and len(parts) == 3:
            record = dict(body or {})
            if entity == state['keyEntity']:
                if record.get('Name') in state.get('failKeyNames', []):
                    return self.reply(412, {'message': 'Something went wrong.'})
                if not record.get('Name'):
                    return self.reply(422, {'message': 'Name is required.'})
            if entity == '_translations':
                if not any(k['Id'] == record.get('Key') for k in state['keys']) or \
                        not any(l['Id'] == record.get('Language') for l in state['languages']) or \
                        not isinstance(record.get('Key'), int) or not isinstance(record.get('Language'), int):
                    return self.reply(422, {'message': 'Key and Language must be existing Ids.'})
            record['Id'] = next_id(rows)
            rows.append(record)
            content = populate_translation(record) if entity == '_translations' else record
            return self.reply(200, {'message': 'Successfully Added.', 'content': content})

        if method == 'PUT' and len(parts) == 4:
            row = next((r for r in rows if str(r['Id']) == parts[3]), None)
            if row is None:
                return self.reply(412, {'message': 'Not found'})
            row.update(body or {})
            return self.reply(200, {'message': 'Successfully Updated.', 'content': row})

        return self.reply(404, {'message': 'Not found'})

    def do_GET(self):
        self.handle_request('GET')

    def do_POST(self):
        self.handle_request('POST')

    def do_PUT(self):
        self.handle_request('PUT')


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
