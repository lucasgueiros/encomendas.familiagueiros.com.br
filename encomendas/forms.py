from django import forms


class ConsultaForm(forms.Form):
    numero = forms.CharField(
        label='Número da encomenda', max_length=64, strip=True,
        help_text='Digite aqui o código de rastreio da Amazon (ex.: TBR...).',
        widget=forms.TextInput(attrs={'placeholder': 'TBR...'}),
    )
