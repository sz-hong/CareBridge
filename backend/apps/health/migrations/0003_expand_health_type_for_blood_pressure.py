from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('health', '0002_healthalert_idx_alert_family_time_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='healthalert',
            name='type',
            field=models.CharField(max_length=32),
        ),
        migrations.AlterField(
            model_name='healthdata',
            name='type',
            field=models.CharField(
                choices=[
                    ('heart_rate', 'Heart Rate'),
                    ('blood_oxygen', 'Blood Oxygen'),
                    ('step_count', 'Step Count'),
                    ('active_energy', 'Active Energy'),
                    ('blood_pressure_systolic', 'Blood Pressure Systolic'),
                    ('blood_pressure_diastolic', 'Blood Pressure Diastolic'),
                ],
                max_length=32,
            ),
        ),
        migrations.AlterField(
            model_name='healthdata',
            name='unit',
            field=models.CharField(
                choices=[
                    ('bpm', 'BPM'),
                    ('%', '%'),
                    ('steps', 'Steps'),
                    ('kcal', 'kcal'),
                    ('mmHg', 'mmHg'),
                ],
                max_length=10,
            ),
        ),
    ]
