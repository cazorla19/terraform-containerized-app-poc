FROM python:3.9.1-alpine as base

FROM base as builder

# Install dependencies
RUN mkdir /install
WORKDIR /install
COPY requirements.txt /requirements.txt
RUN pip install --prefix=/install -r /requirements.txt

FROM base

# Setup the app environment
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC
ENV FLASK_APP="/app/hello.py"

# Setup Nginx and supervisor
RUN apk add -U --no-cache supervisor nginx && \
    rm /etc/nginx/conf.d/default.conf && \
    echo "pid /tmp/nginx.pid; daemon off;" >> /etc/nginx/nginx.conf
COPY config/nginx/ /etc/nginx/conf.d/
COPY config/supervisor/supervisord.conf /etc/supervisord.conf

# Setup non-root user
WORKDIR /app
RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app && \
    chown -R app:app /app && \
    chown -R app:app /tmp && \
    chown -R app:app /var/lib/nginx && \
    chown -R app:app /etc/nginx && \
    chown -R app:app /var/log
USER app

# Setup the app
COPY --from=builder /install /usr/local
COPY src /app

CMD ["/usr/bin/supervisord"]
