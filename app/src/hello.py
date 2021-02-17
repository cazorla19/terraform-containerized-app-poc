from flask import Flask
app = Flask(__name__)

@app.route('/')
def index():
    return 'Index Page'

@app.route('/hello')
def hello():
    return 'Hello, World'

if __name__ == '__main__':
    import logging
    logging.basicConfig(filename='/var/log/app-flask.log',level=logging.DEBUG)

    app.run()