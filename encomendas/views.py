import time

from django.conf import settings
from django.core.cache import cache
from django.shortcuts import render
from django.views.decorators.cache import never_cache

from .forms import ConsultaForm
from .models import Encomenda


def _ip_cliente(request):
    if settings.CONSULTA_USAR_X_FORWARDED_FOR:
        encaminhado = request.META.get('HTTP_X_FORWARDED_FOR', '')
        if encaminhado:
            # O último IP é o adicionado pelo proxy confiável.
            return encaminhado.split(',')[-1].strip()
    return request.META.get('REMOTE_ADDR', '')


def _chave_tentativas(request):
    janela = int(time.time() // settings.CONSULTA_JANELA_SEGUNDOS)
    return f'consulta-tentativas:{_ip_cliente(request)}:{janela}'


def _tentativas(request):
    return cache.get(_chave_tentativas(request), 0)


def _registrar_tentativa(request):
    chave = _chave_tentativas(request)
    cache.set(chave, cache.get(chave, 0) + 1, settings.CONSULTA_JANELA_SEGUNDOS)


@never_cache
def consulta(request):
    form = ConsultaForm(request.POST or None)
    contexto = {'form': form, 'bloqueado': False, 'consultado': False, 'encomenda': None}

    if request.method == 'POST':
        if _tentativas(request) >= settings.CONSULTA_MAX_TENTATIVAS:
            contexto['bloqueado'] = True
            return render(request, 'encomendas/consulta.html', contexto, status=429)

        if form.is_valid():
            _registrar_tentativa(request)
            contexto['consultado'] = True
            contexto['encomenda'] = (
                Encomenda.objects.filter(numero=form.cleaned_data['numero']).first()
            )

    return render(request, 'encomendas/consulta.html', contexto)
