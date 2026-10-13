from django.contrib import admin
from django.urls import path

from encomendas import views

urlpatterns = [
    path('', views.consulta, name='consulta'),
    path('admin/', admin.site.urls),
]
