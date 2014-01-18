describe 'activerecord-mysql-reconnect' do
  it 'select all' do
    expect {
      expect(Employee.all.length).to eq(300024)
      mysql_restart
      expect(Employee.all.length).to eq(300024)
    }.to_not raise_error
  end

  it 'count' do
    expect {
      expect(Employee.count).to eq(300024)
      mysql_restart
      expect(Employee.count).to eq(300024)
    }.to_not raise_error
  end

  it 'on select' do
    expect {
      th = thread_run {|do_stop|
        expect(Employee.where(:id => 1).pluck('sleep(15) * 0')).to eq([0])
      }

      mysql_restart
      expect(Employee.count).to be >= 300024
      th.join
    }.to_not raise_error
  end

  it 'on insert' do
    expect {
      th = thread_run {|do_stop|
        emp = nil

        mysql2_error('MySQL server has gone away') do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => "' + sleep(15) + '",
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
        end

        do_stop.call

        expect(emp.id).to eq(300025)
        expect(emp.emp_no).to eq(1)
      }

      mysql_restart
      expect(Employee.count).to be >= 300024
      th.join
    }.to_not raise_error
  end

  it 'op update' do
    expect {
      th = thread_run {|do_stop|
        emp = Employee.where(:id => 1).first
        emp.first_name = "' + sleep(15) + '"
        emp.last_name = 'ZapZapZap'

        mysql2_error('MySQL server has gone away') do
          emp.save!
        end

        do_stop.call

        emp = Employee.where(:id => 1).first
        expect(emp.last_name).to eq('ZapZapZap')
      }

      mysql_restart
      expect(Employee.count).to eq(300024)
      th.join
    }.to_not raise_error
  end

  it 'without_retry' do
    expect {
      ActiveRecord::Base.without_retry do
        Employee.count
        mysql_restart
        Employee.count
      end
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'transaction' do
    expect {
      expect(Employee.count).to eq(300024)

      mysql2_error('MySQL server has gone away') do
        ActiveRecord::Base.transaction do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(1)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 2,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(2)
        end
      end

      expect(Employee.count).to eq(300025)
    }.to_not raise_error
  end

  it 'retryable_transaction' do
    expect {
      expect(Employee.count).to eq(300024)

      mysql2_error('MySQL server has gone away') do
        ActiveRecord::Base.retryable_transaction do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(1)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 2,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300026)
          expect(emp.emp_no).to eq(2)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 3,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300027)
          expect(emp.emp_no).to eq(3)
        end
      end

      expect(Employee.count).to eq(300027)
    }.to_not raise_error
  end

  it 'retry new connection' do
    expect {
      ActiveRecord::Base.clear_all_connections!
      mysql_restart
      expect(Employee.count).to eq(300024)
    }.to_not raise_error
  end

  it 'retry verify' do
    expect {
      th = thread_run {|do_stop|
        mysql_stop
        sleep 15
        mysql_start
      }

      ActiveRecord::Base.connection.verify!
      th.join
    }.to_not raise_error
  end

  it 'retry reconnect' do
    expect {
      th = thread_run {|do_stop|
        mysql_stop
        sleep 15
        mysql_start
      }

      ActiveRecord::Base.connection.reconnect!
      th.join
    }.to_not raise_error
  end

  it 'disable reconnect' do
    disable_retry do
      expect {
        expect(Employee.all.length).to eq(300024)
        mysql_restart
        expect(Employee.all.length).to eq(300024)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    expect {
      expect(Employee.all.length).to eq(300024)
      mysql_restart
      expect(Employee.all.length).to eq(300024)
    }.to_not raise_error
  end

  it 'read only (read)' do
    enable_read_only do
      expect {
        expect(Employee.all.length).to eq(300024)
        mysql_restart
        expect(Employee.all.length).to eq(300024)
      }.to_not raise_error
    end
  end

  it 'read only (write)' do
    enable_read_only do
      expect {
        th = thread_run {|do_stop|
          mysql2_error('MySQL server has gone away') do
            emp = Employee.create(
                    :emp_no     => 1,
                    :birth_date => Time.now,
                    :first_name => "' + sleep(15) + '",
                    :last_name  => 'Tiger',
                    :hire_date  => Time.now
                  )
          end
        }

        mysql_restart
        th.join
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it 'lost connection' do
    sql = "INSERT INTO `employees` (`birth_date`, `emp_no`, `first_name`, `hire_date`, `last_name`) VALUES ('2014-01-09 03:22:25', 1, '' + sleep(15) + '', '2014-01-09 03:22:25', 'Tiger')"

    expect {
      ActiveRecord::Base.connection.execute(sql)
    }.to_not raise_error

    mysql2_error('Lost connection to MySQL server during query') do
      expect {
        th = thread_run {|do_stop|
          ActiveRecord::Base.connection.execute(sql)
        }

        mysql_restart
        th.join
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it 'force retry' do
    sql = "INSERT INTO `employees` (`birth_date`, `emp_no`, `first_name`, `hire_date`, `last_name`) VALUES ('2014-01-09 03:22:25', 1, '' + sleep(15) + '', '2014-01-09 03:22:25', 'Tiger')"

    expect {
      ActiveRecord::Base.connection.execute(sql)
    }.to_not raise_error

    mysql2_error('Lost connection to MySQL server during query') do
      expect {
        th = thread_run {|do_stop|
          force_retry do
            ActiveRecord::Base.connection.execute(sql)
          end
        }

        mysql_restart
        th.join
      }.to_not raise_error
    end
  end

  it 'read-only=1' do
    mysql2_error('The MySQL server is running with the --read-only option so it cannot execute this statement:') do
      expect {
        expect(Employee.all.length).to eq(300024)
        mysql_restart
        expect(Employee.all.length).to eq(300024)
      }.to_not raise_error
    end
  end
end
