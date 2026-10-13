from django.contrib.auth.models import Group, User
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse

from .models import Encomenda


@override_settings(
    CACHES={'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}},
    CONSULTA_MAX_TENTATIVAS=3,
)
class ConsultaTests(TestCase):
    def setUp(self):
        cache.clear()
        dono = User.objects.create_user('ana', password='x')
        Encomenda.objects.create(dono=dono, numero='BR123', telefone='(81) 99999-0000')

    def consultar(self, numero):
        return self.client.post(reverse('consulta'), {'numero': numero})

    def test_get_mostra_formulario(self):
        resp = self.client.get(reverse('consulta'))
        self.assertContains(resp, 'name="numero"')

    def test_match_exato_mostra_telefone(self):
        resp = self.consultar('BR123')
        self.assertContains(resp, '(81) 99999-0000')
        self.assertContains(resp, 'href="https://wa.me/5581999990000"')

    def test_sem_match_parcial_ou_case_insensitive(self):
        for numero in ['BR12', 'br123', 'BR1234']:
            self.assertNotContains(self.consultar(numero), '99999-0000')

    def test_limite_de_tentativas(self):
        for _ in range(3):
            self.assertEqual(self.consultar('X').status_code, 200)
        resp = self.consultar('BR123')
        self.assertEqual(resp.status_code, 429)
        self.assertNotContains(resp, '99999-0000', status_code=429)


class AdminTests(TestCase):
    def setUp(self):
        grupo = Group.objects.get(name='Donos de encomendas')
        self.ana = User.objects.create_user('ana', password='x', is_staff=True)
        self.bia = User.objects.create_user('bia', password='x', is_staff=True)
        self.ana.groups.add(grupo)
        self.bia.groups.add(grupo)
        self.da_bia = Encomenda.objects.create(dono=self.bia, numero='B1', telefone='2')
        self.client.force_login(self.ana)

    def test_cria_encomenda_para_si(self):
        self.client.post(
            reverse('admin:encomendas_encomenda_add'),
            {'numero': 'A1', 'telefone': '1'},
        )
        self.assertEqual(Encomenda.objects.get(numero='A1').dono, self.ana)

    def test_nao_ve_nem_edita_encomenda_alheia(self):
        lista = self.client.get(reverse('admin:encomendas_encomenda_changelist'))
        self.assertNotContains(lista, 'B1')
        url = reverse('admin:encomendas_encomenda_change', args=[self.da_bia.pk])
        self.client.post(url, {'numero': 'B1', 'telefone': 'hack'})
        self.da_bia.refresh_from_db()
        self.assertEqual(self.da_bia.telefone, '2')

    def test_edita_propria_encomenda(self):
        e = Encomenda.objects.create(dono=self.ana, numero='A2', telefone='1')
        url = reverse('admin:encomendas_encomenda_change', args=[e.pk])
        self.client.post(url, {'numero': 'A2', 'telefone': '9'})
        e.refresh_from_db()
        self.assertEqual(e.telefone, '9')
