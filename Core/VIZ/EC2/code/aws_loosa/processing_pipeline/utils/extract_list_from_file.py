import os


def extract_list_from_file(csv_path, column, delimeter=',', ignore_header=True):
    """
    Extract a column of data from a file (i.e. CSV) based on a delimeter and column.
    Args:
        csv_path(str): The path to the csv file.
        column(int): The column number (1-based) to be extracted.
        delimeter(str): The value on which to separate columns. Defaults to ',' (CSV).
        ignore_header(bool): Ignore first row if True.
    """
    data_list = []

    if not os.path.exists(csv_path):
        raise IOError('The path you specified does not exist: {}'.format(csv_path))

    try:
        column = int(column)
    except (ValueError, TypeError) as exc:
        raise exc

    with open(csv_path, 'r') as csv_file:
        for row_num, row in enumerate(csv_file.readlines()):
            if row_num == 0 and ignore_header:
                continue

            cols = row.split(delimeter)
            num_cols = len(cols)

            if column > num_cols:
                raise ValueError('No such column: {}'.format(column))

            data_list.append(cols[column - 1].strip())

    return data_list
