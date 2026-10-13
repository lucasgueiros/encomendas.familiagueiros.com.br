from django.conf import settings
from django.db import models


class Encomenda(models.Model):
    dono = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='encomendas',
    )
    numero = models.CharField('número', max_length=64, unique=True)
    telefone = models.CharField(max_length=32)
    criado_em = models.DateTimeField('criado em', auto_now_add=True)
    atualizado_em = models.DateTimeField('atualizado em', auto_now=True)

    class Meta:
        verbose_name = 'encomenda'
        verbose_name_plural = 'encomendas'
        ordering = ['-criado_em']

    def __str__(self):
        return self.numero

    def save(self, *args, **kwargs):
        self.numero = self.numero.strip()
        self.telefone = self.telefone.strip()
        super().save(*args, **kwargs)
