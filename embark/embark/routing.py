from django.urls import path
# from django.urls import re_path
# from django.conf.urls import url
from embark.consumers import WSConsumer

# url patterns for websocket communication -> equivalent to urls.py
ws_urlpatterns = [
    path('ws/progress/', WSConsumer.as_asgi())
]
