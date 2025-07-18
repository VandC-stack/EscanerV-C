from datetime import datetime

class AuditoriaLogger:
    def __init__(self, db_manager):
        self.db_manager = db_manager

    def registrar_accion(self, usuario, accion, detalles=None):
        try:
            query = """
                INSERT INTO auditoria (usuario, accion, detalles, fecha)
                VALUES (%s, %s, %s, %s)
            """
            fecha = datetime.now()
            self.db_manager.execute_query(query, (usuario, accion, detalles, fecha), fetch=False)
        except Exception as e:
            # Aquí podrías loguear a un archivo si falla la auditoría
            print(f"Error registrando auditoría: {e}") 