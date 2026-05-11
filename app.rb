# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'bigdecimal'

# Константы формулы
CONST_B = 340
CONST_C = 1.07
CONST_X = 3**(1.0 / 3.0) # 3^(1/3)

# Диапазоны входных значений
RANGES = {
  a: { min: 0.8, min_inclusion: true, max: 1.17, max_inclusion: true, step: 0.01 },
  d: { min: 2, min_inclusion: true, max: 5.13, max_inclusion: true, step: 0.01 },
  f: { min: -12, min_inclusion: true, max: 144, max_inclusion: true, step: 12 }
}.freeze

# Приведение числа к точности Float32 (IEEE 754 single precision)
def f32(val)
  # В Ruby используем to_f для приближения float32
  # Для более точной эмуляции можно использовать pack/unpack
  [val].pack('f').unpack1('f')
end

# Валидация входного значения
def validate_input(value, range)
  min_valid = range[:min_inclusion] ? value >= range[:min] : value > range[:min]
  max_valid = range[:max_inclusion] ? value <= range[:max] : value < range[:max]

  steps = ((value - range[:min]) / range[:step]).round
  is_discrete = ((range[:min] + steps * range[:step]) - value).abs < 1e-8

  min_valid && max_valid && is_discrete
end

# Вычисление формулы a*x^4 + b^(1/6)*x^3 + c*x^2 + (d*x)/f в точности Float32
def calculate_result(a, d, f)
  # Входы и константы приводим к float32
  a_f = f32(a)
  d_f = f32(d)
  f_f = f32(f)
  b_f = f32(CONST_B)
  c_f = f32(CONST_C)
  x_f = f32(CONST_X)

  return 'Ошибка: деление на ноль (f = 0)' if f_f.zero?

  x2 = f32(x_f * x_f)
  x3 = f32(x2 * x_f)
  x4 = f32(x3 * x_f)

  b_sixth = f32(b_f**(1.0 / 6.0))

  term1 = f32(a_f * x4)
  term2 = f32(b_sixth * x3)
  term3 = f32(c_f * x2)
  term4 = f32(f32(d_f * x_f) / f_f)

  # Накопление суммы тоже в float32
  f32(f32(f32(term1 + term2) + term3) + term4)
rescue StandardError => e
  "Ошибка: #{e.message}"
end

# Форматирование числа как "10^{p}" (округление до ближайшей степени десяти)
def format_power_of_ten(value)
  return value.to_s unless value.finite?
  return '0' if value.zero?

  exp = Math.log10(value.abs).round
  "10^{#{exp}}"
end

get '/' do
  erb :index
end

# API endpoint для расчета
post '/calculate' do
  content_type :json

  data = JSON.parse(request.body.read)

  a = data['a'].to_f
  d = data['d'].to_f
  f = data['f'].to_f

  # Валидация
  errors = {}
  errors[:a] = 'Значение должно быть больше или равно 0.8 и меньше или равно 1.17, с шагом 0.01' unless validate_input(a, RANGES[:a])
  errors[:d] = 'Значение должно быть больше или равно 2 и меньше или равно 5.13, с шагом 0.01' unless validate_input(d, RANGES[:d])
  errors[:f] = 'Значение должно быть больше или равно -12 и меньше или равно 144, с шагом 12' unless validate_input(f, RANGES[:f])

  if errors.any?
    status 400
    { errors: errors }.to_json
  else
    result = calculate_result(a, d, f)
    {
      a: a,
      d: d,
      f: f,
      result: result
    }.to_json
  end
end

# API endpoint для загрузки файла
post '/load-file' do
  content_type :json

  if params[:file]
    content = params[:file][:tempfile].read
    begin
      data = JSON.parse(content)

      if !data['sets'] || !data['sets'].is_a?(Array) || data['sets'].empty?
        status 400
        { error: 'Неверный формат файла. Файл должен содержать массив "sets" с наборами аргументов.' }.to_json
      else
        # Валидация данных
        is_valid = data['sets'].all? do |set|
          set['a'].is_a?(Numeric) && set['d'].is_a?(Numeric) && set['f'].is_a?(Numeric)
        end

        if is_valid
          {
            sets: data['sets'],
            file_name: params[:file][:filename]
          }.to_json
        else
          status 400
          { error: 'Один или несколько наборов содержат некорректные данные.' }.to_json
        end
      end
    rescue JSON::ParserError
      status 400
      { error: 'Ошибка при чтении файла. Убедитесь, что файл содержит корректный JSON.' }.to_json
    end
  else
    status 400
    { error: 'Файл не загружен' }.to_json
  end
end
