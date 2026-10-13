from django.contrib import admin

from .models import Encomenda


@admin.register(Encomenda)
class EncomendaAdmin(admin.ModelAdmin):
    list_display = ['numero', 'telefone', 'dono', 'criado_em']
    search_fields = ['numero', 'telefone']
    readonly_fields = ['criado_em', 'atualizado_em']

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_superuser:
            return qs
        return qs.filter(dono=request.user)

    def get_fields(self, request, obj=None):
        fields = ['numero', 'telefone', 'criado_em', 'atualizado_em']
        if request.user.is_superuser:
            fields.insert(0, 'dono')
        return fields

    def get_list_display(self, request):
        if request.user.is_superuser:
            return self.list_display
        return [f for f in self.list_display if f != 'dono']

    def get_list_filter(self, request):
        return ['dono'] if request.user.is_superuser else []

    def save_model(self, request, obj, form, change):
        if not change and not request.user.is_superuser:
            obj.dono = request.user
        super().save_model(request, obj, form, change)

    def _e_dono(self, request, obj):
        return obj is None or request.user.is_superuser or obj.dono_id == request.user.pk

    def has_view_permission(self, request, obj=None):
        return super().has_view_permission(request, obj) and self._e_dono(request, obj)

    def has_change_permission(self, request, obj=None):
        return super().has_change_permission(request, obj) and self._e_dono(request, obj)

    def has_delete_permission(self, request, obj=None):
        return super().has_delete_permission(request, obj) and self._e_dono(request, obj)
