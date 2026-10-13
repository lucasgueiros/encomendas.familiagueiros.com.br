from django import forms


class ConsultaForm(forms.Form):
    numero = forms.CharField(label='Número da encomenda', max_length=64, strip=True)
