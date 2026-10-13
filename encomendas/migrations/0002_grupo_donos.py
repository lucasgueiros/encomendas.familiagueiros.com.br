from django.contrib.auth.management import create_permissions
from django.db import migrations

NOME_GRUPO = 'Donos de encomendas'
PERMISSOES = ['add_encomenda', 'change_encomenda', 'view_encomenda']


def criar_grupo(apps, schema_editor):
    # As permissões normalmente só são criadas no post_migrate; garante que já existam.
    app_config = apps.get_app_config('encomendas')
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    Group = apps.get_model('auth', 'Group')
    Permission = apps.get_model('auth', 'Permission')
    grupo, _ = Group.objects.get_or_create(name=NOME_GRUPO)
    grupo.permissions.add(
        *Permission.objects.filter(
            content_type__app_label='encomendas', codename__in=PERMISSOES
        )
    )


def remover_grupo(apps, schema_editor):
    apps.get_model('auth', 'Group').objects.filter(name=NOME_GRUPO).delete()


class Migration(migrations.Migration):
    dependencies = [
        ('encomendas', '0001_inicial'),
        ('auth', '0012_alter_user_first_name_max_length'),
        ('contenttypes', '0002_remove_content_type_name'),
    ]

    operations = [migrations.RunPython(criar_grupo, remover_grupo)]
